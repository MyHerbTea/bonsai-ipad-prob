import Foundation
import Darwin
import llama

enum SmokeProfile: String, CaseIterable, Identifiable {
    case metal = "Ultra Metal", cpu = "Ultra CPU"
    var id: String { rawValue }
    var gpuLayers: Int32 { self == .metal ? 99 : 0 }
}

enum SmokeError: LocalizedError {
    case modelLoadFailed, contextCreateFailed, tokenizeFailed, promptTooLong(Int), decodeFailed(Int32), emptyOutput
    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: return "模型加载失败。"
        case .contextCreateFailed: return "Context 创建失败。"
        case .tokenizeFailed: return "Prompt tokenization 失败。"
        case .promptTooLong(let n): return "Prompt 为 \(n) tokens，超过 n_batch=16。"
        case .decodeFailed(let rc): return "llama_decode() 失败，return code=\(rc)。"
        case .emptyOutput: return "模型没有生成有效文本。"
        }
    }
}

struct SmokeResult: Sendable {
    let output: String; let generatedTokens: Int; let ttftSeconds: Double
    let generationSeconds: Double; let tokensPerSecond: Double
    let modelSizeGiB: Double; let paramsB: Double
}

actor UltraSmokeEngine {
    private var model: OpaquePointer?, context: OpaquePointer?, vocab: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?, batch: llama_batch?
    private var scopedURL: URL?; private var hasScope=false; private var backendInitialized=false

    private func mark(_ s:String){ UserDefaults.standard.set(s, forKey:"BonsaiUltraSmokeLastStage"); UserDefaults.standard.synchronize() }

    func prepare(url:URL, profile:SmokeProfile) throws {
        unload(); setenv("GGML_METAL_TENSOR_DISABLE","1",1); mark("01_ENV_SET")
        if !backendInitialized { mark("02_BACKEND_INIT_BEGIN"); llama_backend_init(); backendInitialized=true; mark("03_BACKEND_INIT_DONE") }
        let scope=url.startAccessingSecurityScopedResource(); scopedURL=url; hasScope=scope; mark("04_FILE_SCOPE_DONE")
        var mp=llama_model_default_params(); mp.n_gpu_layers=profile.gpuLayers; mp.load_mode=LLAMA_LOAD_MODE_MMAP
        mark("05_MODEL_LOAD_BEGIN")
        guard let m=llama_model_load_from_file(url.path,mp) else { mark("05_MODEL_LOAD_NULL"); stopScope(); throw SmokeError.modelLoadFailed }
        mark("06_MODEL_LOAD_DONE")
        var cp=llama_context_default_params(); cp.n_ctx=256; cp.n_batch=16; cp.n_ubatch=16; cp.n_seq_max=1; cp.n_outputs_max=1; cp.n_outputs_max_per_seq=1; cp.swa_full=false
        if profile == .metal { cp.flash_attn_type=LLAMA_FLASH_ATTN_TYPE_ENABLED; cp.offload_kqv=true; cp.op_offload=true }
        else { cp.flash_attn_type=LLAMA_FLASH_ATTN_TYPE_DISABLED; cp.offload_kqv=false; cp.op_offload=false }
        let threads=max(1,min(4,ProcessInfo.processInfo.processorCount-2)); cp.n_threads=Int32(threads); cp.n_threads_batch=Int32(threads)
        mark("07_CONTEXT_CREATE_BEGIN")
        guard let c=llama_init_from_model(m,cp) else { mark("07_CONTEXT_CREATE_NULL"); llama_model_free(m); stopScope(); throw SmokeError.contextCreateFailed }
        mark("08_CONTEXT_CREATE_DONE")
        let v=llama_model_get_vocab(m); let sp=llama_sampler_chain_default_params(); let s=llama_sampler_chain_init(sp); llama_sampler_chain_add(s,llama_sampler_init_greedy())
        model=m; context=c; vocab=v; sampler=s; batch=llama_batch_init(16,0,1); mark("09_ENGINE_READY")
    }

    func runSmoke(prompt:String="Hello", maxNewTokens:Int=16) throws -> SmokeResult {
        guard let m=model, let c=context, let v=vocab, let s=sampler, var b=batch else { throw SmokeError.contextCreateFailed }
        let pts=try tokenize(prompt,v); guard !pts.isEmpty else { throw SmokeError.tokenizeFailed }; guard pts.count<=16 else { throw SmokeError.promptTooLong(pts.count) }
        llama_memory_clear(llama_get_memory(c),true); llama_sampler_reset(s); clear(&b)
        for i in 0..<pts.count { add(&b,pts[i],Int32(i), i==pts.count-1) }
        mark("10_PROMPT_DECODE_BEGIN"); let start=DispatchTime.now().uptimeNanoseconds
        let r0=llama_decode(c,b); guard r0==0 else { mark("10_PROMPT_DECODE_FAIL_\(r0)"); batch=b; throw SmokeError.decodeFailed(r0) }
        mark("11_PROMPT_DECODE_DONE")
        var out=""; var pending:[CChar]=[]; var ncur=Int32(pts.count); var gen=0; var first:UInt64?=nil; let genStart=DispatchTime.now().uptimeNanoseconds
        while gen<maxNewTokens {
            let tok=llama_sampler_sample(s,c,b.n_tokens-1); if llama_vocab_is_eog(v,tok) { break }
            if first==nil { first=DispatchTime.now().uptimeNanoseconds; mark("12_FIRST_TOKEN_SAMPLED") }
            pending += piece(v,tok); if let t=String(validatingUTF8:pending+[0]) { out += t; pending.removeAll(keepingCapacity:true) }
            clear(&b); add(&b,tok,ncur,true); let rc=llama_decode(c,b); guard rc==0 else { mark("13_TOKEN_DECODE_FAIL_\(rc)"); batch=b; throw SmokeError.decodeFailed(rc) }
            gen+=1; ncur+=1; mark("13_TOKEN_DECODE_\(gen)")
        }
        if !pending.isEmpty { out += String(decoding:pending.map{UInt8(bitPattern:$0)}, as:UTF8.self) }
        batch=b; guard !out.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { mark("14_EMPTY_OUTPUT"); throw SmokeError.emptyOutput }
        let end=DispatchTime.now().uptimeNanoseconds; let f=first ?? end; let ttft=Double(f-start)/1e9; let gs=max(0.000001,Double(end-genStart)/1e9); mark("15_SMOKE_PASS")
        return SmokeResult(output:out,generatedTokens:gen,ttftSeconds:ttft,generationSeconds:gs,tokensPerSecond:Double(gen)/gs,modelSizeGiB:Double(llama_model_size(m))/1073741824.0,paramsB:Double(llama_model_n_params(m))/1e9)
    }

    func unload(){ if let s=sampler { llama_sampler_free(s); sampler=nil }; if let b=batch { llama_batch_free(b); batch=nil }; if let c=context { llama_free(c); context=nil }; if let m=model { llama_model_free(m); model=nil }; vocab=nil; stopScope() }
    private func stopScope(){ if hasScope, let u=scopedURL { u.stopAccessingSecurityScopedResource() }; hasScope=false; scopedURL=nil }
    private func tokenize(_ text:String,_ v:OpaquePointer) throws->[llama_token]{ let n=text.utf8.count; let cap=max(32,n+16); let p=UnsafeMutablePointer<llama_token>.allocate(capacity:cap); defer{p.deallocate()}; let c=llama_tokenize(v,text,Int32(n),p,Int32(cap),true,true); guard c>=0 else{throw SmokeError.tokenizeFailed}; return Array(UnsafeBufferPointer(start:p,count:Int(c))) }
    private func piece(_ v:OpaquePointer,_ t:llama_token)->[CChar]{ var a=[CChar](repeating:0,count:32); let n=llama_token_to_piece(v,t,&a,Int32(a.count),0,true); if n>=0{return Array(a.prefix(Int(n)))}; var b=[CChar](repeating:0,count:Int(-n)); let n2=llama_token_to_piece(v,t,&b,Int32(b.count),0,true); return n2<0 ? [] : Array(b.prefix(Int(n2))) }
    private func clear(_ b:inout llama_batch){ b.n_tokens=0 }
    private func add(_ b:inout llama_batch,_ t:llama_token,_ pos:llama_pos,_ logits:Bool){ let i=Int(b.n_tokens); b.token[i]=t; b.pos[i]=pos; b.n_seq_id[i]=1; b.seq_id[i]![0]=0; b.logits[i]=logits ? 1:0; b.n_tokens+=1 }
}
