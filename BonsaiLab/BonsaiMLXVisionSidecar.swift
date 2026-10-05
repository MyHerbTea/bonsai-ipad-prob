//
// BonsaiMLXVisionSidecar.swift
//
// RC1.22.0 experimental vision-only sidecar.
//
// Vision-tower implementation below is adapted from ml-explore/mlx-swift-lm
// 3.31.3, Libraries/MLXVLM/Models/Qwen3VL.swift.
// Upstream copyright (c) 2024 ml-explore, MIT License.
// See THIRD_PARTY_MLX_VISION_NOTICE.md.
//
// IMPORTANT: This file intentionally contains NO Qwen language model.
// Prism llama.cpp remains the sole 27B language runtime.
//

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import MLX
import MLXNN

// Local equivalent of mlx-swift-lm's public THW transport type.
// Keeping it local means RC1.22 does not have to link the full MLXVLM package.
struct THW: Sendable {
    let t: Int
    let h: Int
    let w: Int

    init(_ t: Int, _ h: Int, _ w: Int) {
        self.t = t
        self.h = h
        self.w = w
    }

    var product: Int {
        t * h * w
    }
}

struct BonsaiMLXVisionConfig: Sendable {
    let depth: Int
    let hiddenSize: Int
    let intermediateSize: Int
    let outHiddenSize: Int
    let numHeads: Int
    let patchSize: Int
    let spatialMergeSize: Int
    let temporalPatchSize: Int
    let numPositionEmbeddings: Int
    let inChannels: Int
    let hiddenAct: String
    let deepstackVisualIndexes: [Int]

    static let bonsai27B = BonsaiMLXVisionConfig(
        depth: 27,
        hiddenSize: 1_152,
        intermediateSize: 4_304,
        outHiddenSize: 5_120,
        numHeads: 16,
        patchSize: 16,
        spatialMergeSize: 2,
        temporalPatchSize: 2,
        numPositionEmbeddings: 2_304,
        inChannels: 3,
        hiddenAct: "gelu_pytorch_tanh",
        deepstackVisualIndexes: []
    )
}

enum BonsaiQwen3VisionSidecarCore {

    static func rotateHalf(_ x: MLXArray) -> MLXArray {
        let half = x.dim(-1) / 2
        let first = x[.ellipsis, 0 ..< half]
        let second = x[.ellipsis, half...]
        return concatenated([-second, first], axis: -1)
    }

    static func applyRotary(_ tensor: MLXArray, freqs: MLXArray) -> MLXArray {
        var cosVals = cos(freqs)
        var sinVals = sin(freqs)

        cosVals = expandedDimensions(cosVals, axis: 1)
        cosVals = tiled(cosVals, repetitions: [1, 1, 2])
        cosVals = expandedDimensions(cosVals, axis: 0)

        sinVals = expandedDimensions(sinVals, axis: 1)
        sinVals = tiled(sinVals, repetitions: [1, 1, 2])
        sinVals = expandedDimensions(sinVals, axis: 0)

        let rotated = (tensor * cosVals) + (rotateHalf(tensor) * sinVals)
        return rotated.asType(tensor.dtype)
    }

    final class VisionRotaryEmbedding {
        let dimension: Int
        let theta: Float

        init(dimension: Int, theta: Float = 10_000) {
            self.dimension = dimension
            self.theta = theta
        }

        func callAsFunction(sequenceLength: Int) -> MLXArray {
            let invFreq =
                1.0
                / pow(
                    MLXArray(theta),
                    MLXArray(stride(from: 0, to: dimension, by: 2)).asType(.float32)
                        / Float(dimension)
                )
            let seq = MLXArray(0 ..< sequenceLength).asType(invFreq.dtype)
            return outer(seq, invFreq)
        }
    }

    final class PatchEmbed: Module, UnaryLayer {
        @ModuleInfo(key: "proj") var proj: Conv3d

        let patchSize: Int
        let temporalPatchSize: Int
        let inChannels: Int
        let hiddenSize: Int

        init(
            patchSize: Int,
            temporalPatchSize: Int,
            inChannels: Int,
            hiddenSize: Int
        ) {
            self.patchSize = patchSize
            self.temporalPatchSize = temporalPatchSize
            self.inChannels = inChannels
            self.hiddenSize = hiddenSize

            let kernel = IntOrTriple([temporalPatchSize, patchSize, patchSize])
            _proj.wrappedValue = Conv3d(
                inputChannels: inChannels,
                outputChannels: hiddenSize,
                kernelSize: kernel,
                stride: kernel,
                bias: true
            )
        }

        func callAsFunction(_ x: MLXArray) -> MLXArray {
            var states = x.reshaped(
                -1,
                inChannels,
                temporalPatchSize,
                patchSize,
                patchSize
            ).movedAxis(source: 1, destination: 4)

            states = proj(states)
            states = states.reshaped(-1, hiddenSize)
            return states
        }
    }

    final class PatchMerger: Module, UnaryLayer {
        let hiddenSize: Int
        let usePostShuffleNorm: Bool

        @ModuleInfo(key: "norm") var norm: LayerNorm
        @ModuleInfo(key: "linear_fc1") var linear1: Linear
        @ModuleInfo(key: "linear_fc2") var linear2: Linear
        @ModuleInfo(key: "act") var activation: GELU

        init(config: BonsaiMLXVisionConfig, usePostShuffleNorm: Bool) {
            self.hiddenSize =
                config.hiddenSize * (config.spatialMergeSize * config.spatialMergeSize)
            self.usePostShuffleNorm = usePostShuffleNorm

            let normDim = usePostShuffleNorm ? hiddenSize : config.hiddenSize
            _norm.wrappedValue = LayerNorm(dimensions: normDim, eps: 1e-6)
            _linear1.wrappedValue = Linear(hiddenSize, hiddenSize)
            _linear2.wrappedValue = Linear(hiddenSize, config.outHiddenSize)
            _activation.wrappedValue = GELU()
        }

        func callAsFunction(_ x: MLXArray) -> MLXArray {
            var states = x
            if usePostShuffleNorm {
                states = states.reshaped(-1, hiddenSize)
            }
            states = norm(states)
            states = states.reshaped(-1, hiddenSize)
            states = linear1(states)
            states = activation(states)
            states = linear2(states)
            return states
        }
    }

    final class Attention: Module {
        let numHeads: Int
        let headDim: Int
        let scale: Float

        @ModuleInfo(key: "qkv") var qkv: Linear
        @ModuleInfo(key: "proj") var proj: Linear

        init(dim: Int, numHeads: Int) {
            self.numHeads = numHeads
            self.headDim = dim / numHeads
            self.scale = pow(Float(headDim), -0.5)

            _qkv.wrappedValue = Linear(dim, 3 * dim, bias: true)
            _proj.wrappedValue = Linear(dim, dim)
        }

        func callAsFunction(
            _ x: MLXArray,
            cuSeqlens: MLXArray,
            rotaryPosEmb: MLXArray
        ) -> MLXArray {
            let sequenceLength = x.dim(0)

            var qkvStates = qkv(x)
            qkvStates = qkvStates.reshaped(sequenceLength, 3, numHeads, headDim)
            qkvStates = qkvStates.transposed(1, 0, 2, 3)

            let parts = split(qkvStates, parts: 3, axis: 0)
            var queries = parts[0][0, 0..., 0..., 0...]
            var keys = parts[1][0, 0..., 0..., 0...]
            var values = parts[2][0, 0..., 0..., 0...]

            queries = applyRotary(queries, freqs: rotaryPosEmb)
            keys = applyRotary(keys, freqs: rotaryPosEmb)

            queries = queries.reshaped(1, sequenceLength, numHeads, headDim).transposed(0, 2, 1, 3)
            keys = keys.reshaped(1, sequenceLength, numHeads, headDim).transposed(0, 2, 1, 3)
            values = values.reshaped(1, sequenceLength, numHeads, headDim).transposed(0, 2, 1, 3)

            var mask = ones([1, sequenceLength, sequenceLength], dtype: queries.dtype)
            mask = mask * MLXArray(-1e9, dtype: queries.dtype)

            let seqlens = cuSeqlens.asArray(Int.self)
            for idx in 1 ..< seqlens.count {
                let start = seqlens[idx - 1]
                let end = seqlens[idx]
                mask[0..., start ..< end, start ..< end] = MLXArray(0, dtype: queries.dtype)
            }

            let attended = MLXFast.scaledDotProductAttention(
                queries: queries,
                keys: keys,
                values: values,
                scale: scale,
                mask: .array(mask)
            )
            .transposed(0, 2, 1, 3)
            .reshaped(sequenceLength, -1)

            return proj(attended)
        }
    }

    final class MLP: Module, UnaryLayer {
        @ModuleInfo(key: "linear_fc1") var linear1: Linear
        @ModuleInfo(key: "linear_fc2") var linear2: Linear
        @ModuleInfo(key: "act") var activation: GELU

        init(dim: Int, hiddenDim: Int) {
            _linear1.wrappedValue = Linear(dim, hiddenDim, bias: true)
            _linear2.wrappedValue = Linear(hiddenDim, dim, bias: true)
            _activation.wrappedValue = GELU(approximation: .fast)
        }

        func callAsFunction(_ x: MLXArray) -> MLXArray {
            linear2(activation(linear1(x)))
        }
    }

    final class VisionBlock: Module {
        @ModuleInfo(key: "norm1") var norm1: LayerNorm
        @ModuleInfo(key: "norm2") var norm2: LayerNorm
        @ModuleInfo(key: "attn") var attention: Attention
        @ModuleInfo(key: "mlp") var mlp: MLP

        init(_ config: BonsaiMLXVisionConfig) {
            _norm1.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: 1e-6)
            _norm2.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: 1e-6)
            _attention.wrappedValue = Attention(dim: config.hiddenSize, numHeads: config.numHeads)
            _mlp.wrappedValue = MLP(dim: config.hiddenSize, hiddenDim: config.intermediateSize)
        }

        func callAsFunction(
            _ hiddenStates: MLXArray,
            cuSeqlens: MLXArray,
            rotaryPosEmb: MLXArray
        ) -> MLXArray {
            var states = hiddenStates
            states =
                states + attention(norm1(states), cuSeqlens: cuSeqlens, rotaryPosEmb: rotaryPosEmb)
            states = states + mlp(norm2(states))
            return states
        }
    }

    final class VisionModel: Module {

        let config: BonsaiMLXVisionConfig
        let spatialMergeSize: Int
        let numGridPerSide: Int

        @ModuleInfo(key: "patch_embed") var patchEmbed: PatchEmbed
        @ModuleInfo(key: "rotary_pos_emb") var rotaryEmbedding: VisionRotaryEmbedding
        @ModuleInfo(key: "pos_embed") var posEmbed: Embedding
        @ModuleInfo(key: "blocks") var blocks: [VisionBlock]
        @ModuleInfo(key: "merger") var merger: PatchMerger
        @ModuleInfo(key: "deepstack_merger_list") var deepstackMergers: [PatchMerger]
        let deepstackVisualIndexes: [Int]

        init(_ config: BonsaiMLXVisionConfig) {
            self.config = config
            self.spatialMergeSize = config.spatialMergeSize
            self.numGridPerSide = Int(sqrt(Double(config.numPositionEmbeddings)))
            self.deepstackVisualIndexes = config.deepstackVisualIndexes

            _patchEmbed.wrappedValue = PatchEmbed(
                patchSize: config.patchSize,
                temporalPatchSize: config.temporalPatchSize,
                inChannels: config.inChannels,
                hiddenSize: config.hiddenSize)

            let headDim = config.hiddenSize / config.numHeads
            _rotaryEmbedding.wrappedValue = VisionRotaryEmbedding(dimension: headDim / 2)

            _posEmbed.wrappedValue = Embedding(
                embeddingCount: config.numPositionEmbeddings,
                dimensions: config.hiddenSize)

            _blocks.wrappedValue = (0 ..< config.depth).map { _ in VisionBlock(config) }
            _merger.wrappedValue = PatchMerger(config: config, usePostShuffleNorm: false)

            _deepstackMergers.wrappedValue = config.deepstackVisualIndexes.map { _ in
                PatchMerger(config: config, usePostShuffleNorm: true)
            }
        }

        private func rotaryPositionEmbedding(_ grids: [THW]) -> MLXArray {
            guard let maxHW = grids.map({ max($0.h, $0.w) }).max(), maxHW > 0 else {
                return MLXArray.zeros([1, 1], dtype: .float32)
            }

            let freqTable = rotaryEmbedding(sequenceLength: maxHW)
            let halfDim = freqTable.dim(-1)

            let merge = spatialMergeSize
            var allCoords: [MLXArray] = []
            let mergeScalar = MLXArray(Int32(merge))

            for grid in grids {
                let mergedH = grid.h / merge
                let mergedW = grid.w / merge

                guard mergedH > 0, mergedW > 0 else { continue }

                // Generate block and intra-block indices fully in MLX
                var blockRows = MLXArray(0 ..< mergedH).asType(.int32)
                blockRows = blockRows.reshaped([mergedH, 1, 1, 1])

                var blockCols = MLXArray(0 ..< mergedW).asType(.int32)
                blockCols = blockCols.reshaped([1, mergedW, 1, 1])

                let intra = MLXArray(0 ..< merge).asType(.int32)
                let intraRow = intra.reshaped([1, 1, merge, 1])
                let intraCol = intra.reshaped([1, 1, 1, merge])

                // Broadcast arithmetic mirrors the Python implementation
                var hIndex = blockRows * mergeScalar + intraRow
                var wIndex = blockCols * mergeScalar + intraCol

                hIndex = broadcast(hIndex, to: [mergedH, mergedW, merge, merge])
                wIndex = broadcast(wIndex, to: [mergedH, mergedW, merge, merge])

                // Flatten and stack coordinate pairs
                let hFlattened = hIndex.flattened()
                let wFlattened = wIndex.flattened()
                var coords = stacked([hFlattened, wFlattened], axis: -1)

                // Repeat for temporal frames
                if grid.t > 1 {
                    coords = tiled(coords, repetitions: [grid.t, 1])
                }

                allCoords.append(coords)
            }

            guard !allCoords.isEmpty else {
                return MLXArray.zeros([0, halfDim * 2], dtype: freqTable.dtype)
            }

            // Concatenate all coordinate pairs
            let allCoordsConcat = concatenated(allCoords, axis: 0)  // (total_tokens, 2)

            // Extract h and w indices and lookup embeddings
            let hIndices = allCoordsConcat[0..., 0].asType(.int32)
            let wIndices = allCoordsConcat[0..., 1].asType(.int32)

            let hEmbeds = freqTable[hIndices, 0...]
            let wEmbeds = freqTable[wIndices, 0...]

            // Concatenate height and width embeddings
            return concatenated([hEmbeds, wEmbeds], axis: -1)
        }

        private func positionalEmbeddings(_ grids: [THW]) -> MLXArray {
            let hiddenSize = config.hiddenSize
            let maxIndex = numGridPerSide - 1

            // Step 1: Collect all indices and weights from all grids using MLX ops
            var cornerIndices: [[MLXArray]] = Array(repeating: [], count: 4)
            var cornerWeights: [[MLXArray]] = Array(repeating: [], count: 4)
            var gridSizes: [Int] = []

            for grid in grids {
                let h = grid.h
                let w = grid.w
                gridSizes.append(h * w)

                // Create linspace indices using broadcasting
                var hLinspace = MLXArray(0 ..< h).asType(.float32)
                hLinspace = hLinspace * MLXArray(Float(maxIndex)) / MLXArray(Float(max(1, h - 1)))

                var wLinspace = MLXArray(0 ..< w).asType(.float32)
                wLinspace = wLinspace * MLXArray(Float(maxIndex)) / MLXArray(Float(max(1, w - 1)))

                // Get floor/ceil and deltas
                let hFloor = hLinspace.asType(.int32)
                let hCeil = minimum(hFloor + 1, maxIndex)
                let dh = hLinspace - hFloor.asType(.float32)

                let wFloor = wLinspace.asType(.int32)
                let wCeil = minimum(wFloor + 1, maxIndex)
                let dw = wLinspace - wFloor.asType(.float32)

                // Broadcast to create meshgrid
                let hFloorExpanded = expandedDimensions(hFloor, axis: 1)  // (h, 1)
                let hCeilExpanded = expandedDimensions(hCeil, axis: 1)
                let wFloorExpanded = expandedDimensions(wFloor, axis: 0)  // (1, w)
                let wCeilExpanded = expandedDimensions(wCeil, axis: 0)

                let baseH = hFloorExpanded * numGridPerSide
                let baseHCeil = hCeilExpanded * numGridPerSide

                // Compute 4 corner indices
                cornerIndices[0].append((baseH + wFloorExpanded).flattened())
                cornerIndices[1].append((baseH + wCeilExpanded).flattened())
                cornerIndices[2].append((baseHCeil + wFloorExpanded).flattened())
                cornerIndices[3].append((baseHCeil + wCeilExpanded).flattened())

                // Compute bilinear weights
                let dhExpanded = expandedDimensions(dh, axis: 1)
                let dwExpanded = expandedDimensions(dw, axis: 0)

                cornerWeights[0].append(((1 - dhExpanded) * (1 - dwExpanded)).flattened())
                cornerWeights[1].append(((1 - dhExpanded) * dwExpanded).flattened())
                cornerWeights[2].append((dhExpanded * (1 - dwExpanded)).flattened())
                cornerWeights[3].append((dhExpanded * dwExpanded).flattened())
            }

            guard !cornerIndices[0].isEmpty else {
                return MLXArray.zeros([0, hiddenSize], dtype: posEmbed.weight.dtype)
            }

            // Step 2: Batch embedding lookup
            let indicesTensors = cornerIndices.map { concatenated($0, axis: 0).asType(.int32) }
            let weightsTensors = cornerWeights.map {
                concatenated($0, axis: 0).asType(posEmbed.weight.dtype)
            }

            let totalPatches = indicesTensors[0].dim(0)
            var patchPosEmbeds = MLXArray.zeros(
                [totalPatches, hiddenSize], dtype: posEmbed.weight.dtype)

            for cornerIdx in 0 ..< 4 {
                let cornerEmbeds = posEmbed(indicesTensors[cornerIdx])
                let weighted =
                    cornerEmbeds * expandedDimensions(weightsTensors[cornerIdx], axis: -1)
                patchPosEmbeds = patchPosEmbeds + weighted
            }

            // Step 3: Split by grid (like Python lines 344-349)
            var patchPosEmbedsSplit: [MLXArray] = []
            var offset = 0

            for size in gridSizes {
                let slice = patchPosEmbeds[offset ..< (offset + size), 0...]
                patchPosEmbedsSplit.append(slice)
                offset += size
            }

            // Step 4: Process each grid (like Python lines 354-371)
            var resultEmbeds: [MLXArray] = []
            let merge = spatialMergeSize

            for (gridIdx, grid) in grids.enumerated() {
                let posEmbed = patchPosEmbedsSplit[gridIdx]
                let h = grid.h
                let w = grid.w
                let t = grid.t

                let featureDim = posEmbed.dim(-1)

                // Repeat for temporal dimension
                var temporalEmbeds = tiled(posEmbed, repetitions: [t, 1])

                // Reshape for merge pattern
                temporalEmbeds = temporalEmbeds.reshaped(t, h, w, featureDim)
                temporalEmbeds = temporalEmbeds.reshaped(
                    t,
                    h / merge,
                    merge,
                    w / merge,
                    merge,
                    featureDim
                )
                temporalEmbeds = temporalEmbeds.transposed(0, 1, 3, 2, 4, 5)
                temporalEmbeds = temporalEmbeds.reshaped(-1, featureDim)

                resultEmbeds.append(temporalEmbeds)
            }

            return concatenated(resultEmbeds, axis: 0)
        }

        private func cumulativeSequenceLengths(_ grids: [THW]) -> MLXArray {
            var seqLengths: [MLXArray] = []

            for grid in grids {
                let perFrame = grid.h * grid.w
                let repeated = tiled(MLXArray(perFrame), repetitions: [grid.t])
                seqLengths.append(repeated)
            }

            guard !seqLengths.isEmpty else {
                return MLXArray(0, dtype: .int32)
            }

            let concatSeqLengths = concatenated(seqLengths).asType(.int32)

            let cumSum = concatSeqLengths.cumsum()

            return padded(
                cumSum, widths: [IntOrPair((1, 0))], mode: .constant,
                value: MLXArray(0, dtype: cumSum.dtype))
        }

        private func localKey(
            _ rawKey: String
        ) -> String {
            if rawKey.hasPrefix("vision_tower.") {
                return String(
                    rawKey.dropFirst(
                        "vision_tower.".count
                    )
                )
            }
            if rawKey.hasPrefix("model.visual.") {
                return String(
                    rawKey.dropFirst(
                        "model.visual.".count
                    )
                )
            }
            if rawKey.hasPrefix(
                "model.vision_tower."
            ) {
                return String(
                    rawKey.dropFirst(
                        "model.vision_tower.".count
                    )
                )
            }
            return rawKey
        }

        private func loadOneBlockWeights(
            index: Int,
            weightsURL: URL
        ) throws -> [String: MLXArray] {
            // RC1.22.5: reopen the safetensor file per layer so previously
            // materialized block arrays are not kept alive by a long-lived
            // dictionary of MLXArray handles.
            let raw = try MLX.loadArrays(
                url: weightsURL,
                stream: .cpu
            )

            let prefix = "blocks.\(index)."
            var output: [String: MLXArray] = [:]

            for (rawKey, value) in raw {
                let key = localKey(rawKey)
                guard key.hasPrefix(prefix) else {
                    continue
                }
                output[
                    String(
                        key.dropFirst(prefix.count)
                    )
                ] = value
            }

            return output
        }

        private func runHardCutBlock(
            index: Int,
            hiddenStates: MLXArray,
            cuSeqlens: MLXArray,
            rotaryEmbeds: MLXArray,
            weightsURL: URL
        ) throws -> MLXArray {
            let localWeights =
                try loadOneBlockWeights(
                    index: index,
                    weightsURL: weightsURL
                )

            guard !localWeights.isEmpty else {
                throw MLXVisionSidecarError
                    .missingBlockWeights(index)
            }

            let block = VisionBlock(config)
            try block.update(
                parameters:
                    ModuleParameters.unflattened(
                        localWeights
                    ),
                verify: .all
            )

            let output = block(
                hiddenStates,
                cuSeqlens: cuSeqlens,
                rotaryPosEmb: rotaryEmbeds
            )
            eval(output)

            // Hard graph cut: copy the evaluated activation into independent
            // CPU storage and immediately reconstruct a fresh MLXArray.
            // The returned array has no dependency on this block, its loaded
            // weights, or the previous lazy graph.
            let snapshot =
                output.asData(access: .copy)
            return MLXArray(data: snapshot)
        }

        func callAsFunction(
            _ pixelValues: MLXArray,
            gridTHW: [THW],
            weightsURL: URL,
            progress: ((String) -> Void)? = nil
        ) throws -> (MLXArray, [MLXArray]) {
            progress?("MLX_CUT_00_PATCH_BEGIN")
            var hiddenStates = patchEmbed(pixelValues)
            eval(hiddenStates)
            hiddenStates = MLXArray(
                data:
                    hiddenStates.asData(
                        access: .copy
                    )
            )
            Memory.clearCache()
            progress?("MLX_CUT_00_PATCH_DONE")

            let posEmbeds = positionalEmbeddings(gridTHW)
            eval(posEmbeds)
            hiddenStates = hiddenStates + posEmbeds
            eval(hiddenStates)
            hiddenStates = MLXArray(
                data:
                    hiddenStates.asData(
                        access: .copy
                    )
            )
            Memory.clearCache()
            progress?("MLX_CUT_00_POSITION_DONE")

            let rotaryEmbeds =
                rotaryPositionEmbedding(gridTHW)
            let cuSeqlens =
                cumulativeSequenceLengths(gridTHW)
            eval(rotaryEmbeds)
            eval(cuSeqlens)
            Memory.clearCache()
            progress?("MLX_CUT_00_ROTARY_DONE")

            var deepstackOutputs: [MLXArray] = []

            for index in 0 ..< config.depth {
                progress?(
                    String(
                        format: "MLX_CUT_%02d_BEGIN",
                        index + 1
                    )
                )

                hiddenStates =
                    try runHardCutBlock(
                        index: index,
                        hiddenStates: hiddenStates,
                        cuSeqlens: cuSeqlens,
                        rotaryEmbeds:
                            rotaryEmbeds,
                        weightsURL: weightsURL
                    )

                // At this point the activation is a fresh CPU-backed array.
                // The local block + per-layer safetensor handles have fallen
                // out of scope, so clearCache can reclaim their Metal buffers.
                Memory.clearCache()

                progress?(
                    String(
                        format: "MLX_CUT_%02d_DONE",
                        index + 1
                    )
                )
            }

            progress?("MLX_CUT_28_MERGER_BEGIN")
            hiddenStates = merger(hiddenStates)
            eval(hiddenStates)
            hiddenStates = MLXArray(
                data:
                    hiddenStates.asData(
                        access: .copy
                    )
            )
            Memory.clearCache()
            progress?("MLX_CUT_28_MERGER_DONE")

            return (hiddenStates, deepstackOutputs)
        }

        func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
            var sanitized: [String: MLXArray] = [:]
            for (key, value) in weights {
                if key.contains("position_ids") {
                    continue
                } else if key.contains("patch_embed.proj.weight") {
                    if value.ndim == 5 && value.dim(-1) == config.inChannels {
                        sanitized[key] = value
                    } else {
                        sanitized[key] = value.transposed(0, 2, 3, 4, 1)
                    }
                } else {
                    sanitized[key] = value
                }
            }
            return sanitized
        }
    }
}


struct MLXVisionEmbeddingPacket: Sendable {
    let metrics: MLXVisionSidecarMetrics
    let float32Embeddings: Data
    let gridX: Int
    let gridY: Int
}

struct MLXVisionSidecarMetrics: Sendable {
    let weightFile: String
    let sourceWidth: Int
    let sourceHeight: Int
    let resizedWidth: Int
    let resizedHeight: Int
    let rawPatchRows: Int
    let outputTokens: Int
    let outputDimension: Int
    let loadSeconds: Double
    let encodeSeconds: Double
    let activeMemoryMiB: Int
    let cacheMemoryMiB: Int
    let peakMemoryMiB: Int

    var summary: String {
        """
        MLX Vision Sidecar: PASS
        Weights: \(weightFile)
        Source: \(sourceWidth)x\(sourceHeight)
        Resized: \(resizedWidth)x\(resizedHeight)
        Raw patch rows: \(rawPatchRows)
        Vision output: \(outputTokens) x \(outputDimension)
        Weight load: \(String(format: "%.3f", loadSeconds)) s
        Image encode: \(String(format: "%.3f", encodeSeconds)) s
        MLX active/cache/peak: \(activeMemoryMiB)/\(cacheMemoryMiB)/\(peakMemoryMiB) MiB
        """
    }
}

enum MLXVisionSidecarError: LocalizedError {
    case invalidImage
    case invalidDimensions
    case noVisionWeights
    case missingBlockWeights(Int)
    case unexpectedOutput([Int])

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取测试图片。"
        case .invalidDimensions:
            return "图片尺寸不满足 Qwen Vision patch/merge 要求。"
        case .noVisionWeights:
            return "没有找到 vision_tower 权重；请使用 RC1.22 配套抽取脚本生成的 safetensors。"
        case .missingBlockWeights(let index):
            return "缺少 Vision block \(index) 的流式权重。"
        case .unexpectedOutput(let shape):
            return "MLX Vision 输出 shape 异常：\(shape)，期望 [N, 5120]。"
        }
    }
}

actor MLXVisionSidecar {
    private var model: BonsaiQwen3VisionSidecarCore.VisionModel?
    private var loadedWeightsPath: String?

    // Actor isolation makes the otherwise non-Sendable CIContext safe
    // without requiring mlx-swift-lm's Swift-6.2-specific global workaround.
    private let ciContext = CIContext(
        options: [.cacheIntermediates: false]
    )

    private let config = BonsaiMLXVisionConfig.bonsai27B

    private var stageURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: support,
            withIntermediateDirectories: true
        )
        return support.appendingPathComponent(
            "bonsai_mlx_vision_stage.txt"
        )
    }

    private func mark(_ stage: String) {
        try? (stage + "\n").write(
            to: stageURL,
            atomically: true,
            encoding: .utf8
        )

        let allocator =
            "stage=\(stage) "
            + "active=\(Memory.activeMemory / 1_048_576)MiB "
            + "cache=\(Memory.cacheMemory / 1_048_576)MiB "
            + "peak=\(Memory.peakMemory / 1_048_576)MiB "
            + "cacheLimit=\(Memory.cacheLimit / 1_048_576)MiB"

        UserDefaults.standard.set(
            stage,
            forKey: "BonsaiMLXVisionStage"
        )
        UserDefaults.standard.set(
            allocator,
            forKey: "BonsaiMLXVisionLastMetrics"
        )
        UserDefaults.standard.synchronize()
    }

    func releaseResidentStateForContextSwitch() {
        mark("MLX_CTX_SWITCH_00_RELEASE_BEGIN")
        model = nil
        loadedWeightsPath = nil
        Memory.clearCache()
        mark("MLX_CTX_SWITCH_01_RELEASE_DONE")
    }

    private func runAllocatorSmoke() {
        // RC1.22.1 admission gate: prove that a minimal MLX/Metal
        // computation can execute while the Prism 27B runtime is resident
        // before allocating the full vision tower.
        mark("MLX_ADMIT_01_TENSOR_SMOKE_BEGIN")

        // Apple's iOS guidance recommends a small MLX allocator cache on
        // memory-constrained devices. Keep this deliberately tiny during
        // coexistence bring-up to avoid jetsam caused by recycled buffers.
        Memory.cacheLimit = 20 * 1_048_576
        Memory.clearCache()

        let a = MLXArray.ones(
            [256, 256],
            dtype: .float16
        )
        let b = MLXArray.ones(
            [256, 256],
            dtype: .float16
        )
        let c = matmul(a, b)
        eval(c)

        mark("MLX_ADMIT_02_TENSOR_SMOKE_PASS")
        Memory.clearCache()
        mark("MLX_ADMIT_03_CACHE_CLEARED")
    }

    private func inSRGBToneCurveSpace(
        _ image: CIImage
    ) -> CIImage {
        let filter = CIFilter.linearToSRGBToneCurve()
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    private func resampleBicubic(
        _ image: CIImage,
        width: Int,
        height: Int
    ) -> CIImage {
        let target = CGSize(
            width: width,
            height: height
        )
        let yScale =
            target.height / image.extent.height
        let xScale =
            target.width / image.extent.width

        let filter = CIFilter.bicubicScaleTransform()
        filter.inputImage = image
        filter.scale = Float(yScale)
        filter.aspectRatio =
            Float(xScale / yScale)

        let scaled = filter.outputImage ?? image
        return scaled.cropped(
            to: CGRect(
                x: 0,
                y: 0,
                width: target.width,
                height: target.height
            )
        )
    }

    private func normalize(
        _ image: CIImage
    ) -> CIImage {
        // Qwen3.5 processor mean/std = 0.5/0.5/0.5.
        // (x - 0.5) / 0.5 == 2*x - 1.
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(
            x: 2, y: 0, z: 0, w: 0
        )
        filter.gVector = CIVector(
            x: 0, y: 2, z: 0, w: 0
        )
        filter.bVector = CIVector(
            x: 0, y: 0, z: 2, w: 0
        )
        filter.aVector = CIVector(
            x: 0, y: 0, z: 0, w: 1
        )
        filter.biasVector = CIVector(
            x: -1, y: -1, z: -1, w: 0
        )
        return filter.outputImage ?? image
    }

    private func asMLXArray(
        _ image: CIImage
    ) -> MLXArray {
        let width =
            Int(image.extent.width.rounded())
        let height =
            Int(image.extent.height.rounded())

        let components = 4
        let bytesPerPixel = components * 4
        let bytesPerRow = width * bytesPerPixel

        var data = Data(
            count:
                width * height * bytesPerPixel
        )
        data.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else {
                return
            }
            ciContext.render(
                image,
                toBitmap: base,
                rowBytes: bytesPerRow,
                bounds: image.extent,
                format: .RGBAf,
                colorSpace: nil
            )
            ciContext.clearCaches()
        }

        var array = MLXArray(
            data,
            [height, width, 4],
            type: Float32.self
        )
        array = array[
            0..., 0..., ..<3
        ]
        return array
            .reshaped(
                1,
                height,
                width,
                3
            )
            .transposed(0, 3, 1, 2)
    }

    private func targetSize(
        height: Int,
        width: Int,
        maxPixels: Int = 65_536
    ) throws -> (Int, Int) {
        let factor =
            config.patchSize
            * config.spatialMergeSize
        // Admission tier only: keep the first coexistence forward near
        // 256x256 so activation memory cannot obscure the weight-lifetime
        // result. Quality scaling returns after lifecycle PASS.
        let minPixels = 32_768

        guard
            height >= factor,
            width >= factor,
            max(height, width) / max(1, min(height, width)) <= 200
        else {
            throw MLXVisionSidecarError.invalidDimensions
        }

        var h = max(
            factor,
            Int(round(Double(height) / Double(factor)))
                * factor
        )
        var w = max(
            factor,
            Int(round(Double(width) / Double(factor)))
                * factor
        )

        if h * w > maxPixels {
            let beta = sqrt(
                Double(height * width)
                    / Double(maxPixels)
            )
            h =
                Int(
                    floor(
                        Double(height)
                            / beta
                            / Double(factor)
                    )
                )
                * factor
            w =
                Int(
                    floor(
                        Double(width)
                            / beta
                            / Double(factor)
                    )
                )
                * factor
        } else if h * w < minPixels {
            let beta = sqrt(
                Double(minPixels)
                    / Double(height * width)
            )
            h =
                Int(
                    ceil(
                        Double(height)
                            * beta
                            / Double(factor)
                    )
                )
                * factor
            w =
                Int(
                    ceil(
                        Double(width)
                            * beta
                            / Double(factor)
                    )
                )
                * factor
        }

        h = max(factor, (h / factor) * factor)
        w = max(factor, (w / factor) * factor)

        guard h > 0, w > 0 else {
            throw MLXVisionSidecarError.invalidDimensions
        }

        return (h, w)
    }

    private func patchify(
        image: MLXArray
    ) -> (MLXArray, THW) {
        var patches = image
        let temporal = config.temporalPatchSize

        let mod = patches.dim(0) % temporal
        if mod != 0 {
            let last = patches[-1, .ellipsis]
            let repeatedLast = tiled(
                last,
                repetitions: [
                    temporal - mod,
                    1,
                    1,
                    1
                ]
            )
            patches = concatenated(
                [patches, repeatedLast]
            )
        }

        let channel = patches.dim(1)
        let resizedHeight = patches.dim(-2)
        let resizedWidth = patches.dim(-1)

        let gridT = patches.dim(0) / temporal
        let gridH =
            resizedHeight / config.patchSize
        let gridW =
            resizedWidth / config.patchSize
        let merge = config.spatialMergeSize
        let patch = config.patchSize

        patches = patches.reshaped(
            gridT,
            temporal,
            channel,
            gridH / merge,
            merge,
            patch,
            gridW / merge,
            merge,
            patch
        )
        patches = patches.transposed(
            0, 3, 6, 4, 7, 2, 1, 5, 8
        )

        let flattened = patches.reshaped(
            gridT * gridH * gridW,
            channel * temporal * patch * patch
        )

        return (
            flattened,
            THW(gridT, gridH, gridW)
        )
    }

    private func localVisionWeights(
        _ raw: [String: MLXArray]
    ) -> [String: MLXArray] {
        var output: [String: MLXArray] = [:]

        for (rawKey, value) in raw {
            let key: String
            if rawKey.hasPrefix("vision_tower.") {
                key = String(
                    rawKey.dropFirst(
                        "vision_tower.".count
                    )
                )
            } else if rawKey.hasPrefix("model.visual.") {
                key = String(
                    rawKey.dropFirst(
                        "model.visual.".count
                    )
                )
            } else if rawKey.hasPrefix(
                "model.vision_tower."
            ) {
                key = String(
                    rawKey.dropFirst(
                        "model.vision_tower.".count
                    )
                )
            } else {
                // The bundled extraction script already emits
                // module-local keys.
                key = rawKey
            }

            if
                key.hasPrefix("patch_embed.")
                || key.hasPrefix("pos_embed.")
                || key.hasPrefix("blocks.")
                || key.hasPrefix("merger.")
                || key.hasPrefix(
                    "deepstack_merger_list."
                )
            {
                output[key] = value
            }
        }

        return output
    }

    private func ensureLoaded(
        weightsURL: URL
    ) throws -> Double {
        if
            model != nil,
            loadedWeightsPath == weightsURL.path
        {
            mark("MLX_CUT_20_SHELL_RESIDENT_HIT")
            return 0
        }

        runAllocatorSmoke()

        Memory.cacheLimit = 20 * 1_048_576
        Memory.clearCache()

        let start =
            DispatchTime.now().uptimeNanoseconds

        mark("MLX_CUT_10_LOAD_ARRAYS_BEGIN")
        let raw = try MLX.loadArrays(
            url: weightsURL,
            stream: .cpu
        )
        mark("MLX_CUT_11_LOAD_ARRAYS_DONE")

        var weights = localVisionWeights(raw)
        guard !weights.isEmpty else {
            mark("MLX_CUT_12_NO_VISION_WEIGHTS")
            throw MLXVisionSidecarError.noVisionWeights
        }

        mark("MLX_CUT_13_FILTER_WEIGHTS_DONE")

        mark("MLX_CUT_14_MODEL_INIT_BEGIN")
        let created =
            BonsaiQwen3VisionSidecarCore
                .VisionModel(config)
        mark("MLX_CUT_15_MODEL_INIT_DONE")

        mark("MLX_CUT_16_SANITIZE_BEGIN")
        weights = created.sanitize(
            weights: weights
        )
        mark("MLX_CUT_17_SANITIZE_DONE")

        let shellWeights = weights.filter {
            !$0.key.hasPrefix("blocks.")
        }

        mark("MLX_CUT_19_BIND_SHELL_BEGIN")
        try created.update(
            parameters:
                ModuleParameters.unflattened(
                    shellWeights
                ),
            verify: [
                .noUnusedKeys,
                .shapeMismatch
            ]
        )
        mark("MLX_CUT_20_BIND_SHELL_DONE")

        // Do not retain any blocks.* MLXArray handles beyond this function.
        // raw/weights/block arrays are released as ensureLoaded returns.
        model = created
        loadedWeightsPath = weightsURL.path

        Memory.clearCache()

        let end =
            DispatchTime.now().uptimeNanoseconds
        mark("MLX_CUT_24_SHELL_READY")
        return Double(end - start)
            / 1_000_000_000.0
    }

    func encodeForInjection(
        weightsURL: URL,
        imageURL: URL
    ) throws -> MLXVisionEmbeddingPacket {
        let weightScope =
            weightsURL.startAccessingSecurityScopedResource()
        let imageScope =
            imageURL.startAccessingSecurityScopedResource()
        defer {
            if weightScope {
                weightsURL
                    .stopAccessingSecurityScopedResource()
            }
            if imageScope {
                imageURL
                    .stopAccessingSecurityScopedResource()
            }
        }

        mark("MLX_ADMIT_00_BEGIN")

        let loadSeconds = try ensureLoaded(
            weightsURL: weightsURL
        )

        guard
            let model,
            var image = CIImage(
                contentsOf: imageURL,
                options: [
                    .applyOrientationProperty: true
                ]
            )
        else {
            mark("MLX_VISION_03_IMAGE_FAIL")
            throw MLXVisionSidecarError.invalidImage
        }

        let sourceWidth =
            Int(image.extent.width.rounded())
        let sourceHeight =
            Int(image.extent.height.rounded())

        let (targetHeight, targetWidth) =
            try targetSize(
                height: sourceHeight,
                width: sourceWidth
            )

        mark("MLX_ADMIT_30_PREPROCESS_BEGIN")

        image =
            inSRGBToneCurveSpace(image)
        image =
            resampleBicubic(
                image,
                width: targetWidth,
                height: targetHeight
            )
        image = normalize(image)

        let planar = asMLXArray(image)
        var (patches, frame) =
            patchify(image: planar)

        patches = patches.asType(
            model.patchEmbed.proj.weight.dtype
        )

        Memory.clearCache()
        mark("MLX_CUT_30_PRE_FORWARD_READY")
        mark("MLX_CUT_40_FORWARD_BEGIN")
        let start =
            DispatchTime.now().uptimeNanoseconds

        let (hidden, _) = try model(
            patches,
            gridTHW: [frame],
            weightsURL: weightsURL,
            progress: { stage in
                self.mark(stage)
            }
        )

        let end =
            DispatchTime.now().uptimeNanoseconds
        mark("MLX_CUT_99_FORWARD_DONE")

        let shape = hidden.shape
        guard
            shape.count == 2,
            shape[1] == config.outHiddenSize
        else {
            mark("MLX_LAZY_42_SHAPE_FAIL")
            throw MLXVisionSidecarError
                .unexpectedOutput(shape)
        }

        let metrics = MLXVisionSidecarMetrics(
            weightFile:
                weightsURL.lastPathComponent,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            resizedWidth: targetWidth,
            resizedHeight: targetHeight,
            rawPatchRows: patches.dim(0),
            outputTokens: shape[0],
            outputDimension: shape[1],
            loadSeconds: loadSeconds,
            encodeSeconds:
                Double(end - start)
                / 1_000_000_000.0,
            activeMemoryMiB:
                Memory.activeMemory / 1_048_576,
            cacheMemoryMiB:
                Memory.cacheMemory / 1_048_576,
            peakMemoryMiB:
                Memory.peakMemory / 1_048_576
        )

        UserDefaults.standard.set(
            metrics.summary,
            forKey: "BonsaiMLXVisionLastMetrics"
        )
        UserDefaults.standard.synchronize()

        mark("MLX_INJECT_01_F32_COPY_BEGIN")
        let hiddenF32 = hidden.asType(.float32)
        eval(hiddenF32)
        let embeddingData =
            hiddenF32.asData(access: .copy).data

        let gridX =
            frame.w / config.spatialMergeSize
        let gridY =
            frame.h / config.spatialMergeSize

        guard
            gridX > 0,
            gridY > 0,
            gridX * gridY == shape[0],
            embeddingData.count ==
                shape[0] * shape[1] * MemoryLayout<Float>.size
        else {
            mark("MLX_INJECT_02_PACKET_SHAPE_FAIL")
            throw MLXVisionSidecarError
                .unexpectedOutput(shape)
        }

        Memory.clearCache()
        mark("MLX_INJECT_03_PACKET_READY")

        return MLXVisionEmbeddingPacket(
            metrics: metrics,
            float32Embeddings: embeddingData,
            gridX: gridX,
            gridY: gridY
        )
    }

    func cleanupAfterRequestFailure() {
        Memory.clearCache()
        mark("MLX_API_FAIL_CLEANUP")
    }

    func probe(
        weightsURL: URL,
        imageURL: URL
    ) throws -> MLXVisionSidecarMetrics {
        let packet = try encodeForInjection(
            weightsURL: weightsURL,
            imageURL: imageURL
        )
        mark("MLX_HARDCUT_99_PASS")
        return packet.metrics
    }
}
