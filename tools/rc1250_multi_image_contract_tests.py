from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
normalizer = (root / "BonsaiLab" / "OpenAIMultimodal.swift").read_text()
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
composer = (root / "BonsaiLab" / "OpenAIMultiImageComposer.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

assert "struct OpenAIImageInput" in normalizer
assert "let images: [OpenAIImageInput]" in normalizer
assert "guard images.count < 3" in normalizer
assert "if totalImages > 3" in normalizer
assert "case multiple" in normalizer
assert "RC1.25.0 每个请求最多支持三张图片。" in normalizer

assert "let images: [OpenAIImageInput]" in server
assert "var imageCount: Int" in server
if "RC1.25.2" in view:
    assert "visualUser?.images ?? []" in server
    assert "totalImages = max(" in server
else:
    assert "images = parsed.images" in server
assert "if totalImages > 3" in server

assert "enum OpenAIMultiImageComposer" in composer
assert "static let canvasWidth = 1_024" in composer
assert "static let canvasHeight = 512" in composer
assert "kCGImageSourceCreateThumbnailWithTransform" in composer
assert 'layout:' in composer
assert '"left-right"' in composer
assert '"left-center-right"' in composer

assert 'requestRoute = "vision_multi"' in view
assert "OpenAIMultiImageComposer" in view
assert ".compose(payload.images)" in view
assert "payload.imageCount" in view
assert "BonsaiRC1250LastAPIImageCount" in view
assert "BonsaiRC1250LastMultiImageLayout" in view
assert "[RC1.25.0 MULTI-IMAGE]" in view
assert "max_images_per_request=3" in view
assert "bounded_contact_sheet_before_vision_tower" in view
assert (
    'Text("1.0 · RC1.25.0 Multi-Image OpenAI API")' in view
    or 'Text("1.0 · RC1.25.1 API Hardening")' in view
    or 'Text("1.0 · RC1.25.2 Build 63 Vision Lifecycle Safety")' in view
)

# Production runtime remains the proven Full profile by default.
assert 'private var apiRuntimeProfile = "accelerated"' in view

match = re.search(r'CURRENT_PROJECT_VERSION:\s*"([0-9]+)"', project)
assert match is not None
assert int(match.group(1)) >= 57

assert "lab-v1-rc1-25-0-multi-image-openai-api" in workflow
assert "RC1.25.0 multi-image contracts" in workflow
assert "tools/rc1250_multi_image_contract_tests.py" in workflow
assert "tools/rc1250_multi_image_composer_contract_tests.swift" in workflow
assert "tools/rc1250_multi_image_contract_tests.py" in workflow

print("RC1.25.0 Build 57 multi-image source contracts: PASS")
