# 앱 및 탭 아이콘

## 앱 아이콘

`AppIcon.appiconset/AppIcon.png`은 1024×1024 불투명 RGB 원본입니다. iOS가 continuous-corner 마스크를 적용하므로 원본에는 둥근 외곽, 투명 모서리, 외부 그림자를 넣지 않습니다.

Horizon 디자인은 코발트·애저 블루 글래스 배경 위에 오른쪽으로 완만하게 상승하는 두 개의 frosted horizon 곡선을 사용합니다. 장기 자산 성장과 누적 기록을 표현하며 막대그래프·화살표·통화 기호는 사용하지 않습니다. 앱 기본 포인트 컬러는 같은 코발트 블루이고 그래프 롱프레스 선택 상태만 그린으로 전환합니다.

내장 이미지 생성 도구에 사용한 최종 프롬프트 요약:

> Production iOS icon, opaque square full-bleed artwork. Preserve the approved Horizon concept: sapphire-to-azure layered glass background and two smooth frosted white/pale-blue curves rising to the right. Keep the curves in the central safe area and readable at 48px. No pre-rounded corners, transparency, outer shadow, text, bars, axes, arrows, coins, green, purple, red, orange, or watermark.

## 탭 아이콘

내장 image_gen 도구로 생성한 원본입니다. 단색·투명 배경을 유지하고 런타임에서 template tint를 적용합니다. 탭 이미지에는 생성 이미지의 84px 파생본을 3x(28pt)로 사용합니다. 선택 시 SOXL은 앱의 코발트 블루, HYXL은 인디고이며 비선택 상태는 시스템 색상입니다.

- [SOXL 원본](soxl-icon-source.png): 반도체 칩과 투명한 상승 화살표.
- [HYXL 원본](hyxl-icon-source.png): 하이닉스를 연상시키는 H 메모리칩. 공식 하이닉스 로고는 아닙니다.
- 앱 에셋: `SOXLTab.imageset`, `HYXLTab.imageset`.

## 최종 생성 프롬프트

### SOXL

Use case: logo-brand. Generate one clean monochrome template icon image for an iOS tab bar destination called SOXL, a semiconductor investment. Single black glyph on genuinely transparent alpha background. A bold simple rounded-square microchip with three short pins per edge, with one clearly legible ascending diagonal arrow as transparent negative space in its solid central chip. The arrow has a chunky elbow-free rising diagonal shaft and arrowhead. Optical weight like SF Symbols medium-filled icon at 25pt. Flat 2D geometrical silhouette, consistent rounded pin terminals, perfect balanced symmetry of chip outline, pixel-crisp antialiasing. Glyph occupies about 82% of a square 1024x1024 canvas with equal transparent margins. Only one icon, pure black opacity mask, absolutely no colors, gray shadows, gradient, emboss, border tile, badge, textual letters or label, mockup, checkerboard background or company logo. The arrow should be legible even at 25x25 points.

### HYXL

Use case: logo-brand. Generate one clean monochrome template icon image for an iOS tab bar destination HYXL associated with Hynix memory semiconductors. Single black glyph on genuinely transparent alpha background. A bold geometric capital H memory-chip monogram: two upright vertical rounded black rails joined by one strong horizontal midbar, with three short horizontal memory-contact pins projecting outward from each outer vertical edge, and subtle chip-like short vertical terminals on top and bottom. The capital H must remain unmistakably readable in its overall silhouette and its open upper and lower gaps. Optical weight and simplicity like SF Symbols medium-filled at 25pt, balanced geometric proportions. Flat 2D pure black shape, terminals gently rounded, crisp edges, no extra micro details. Glyph occupies about 82% of a square 1024x1024 canvas with equal transparent margins. Only one icon, pure black opacity mask, no colors, gray shadows, gradients, emboss, background tile, badge, label, other text, mockup, checkerboard background, or actual company wordmark. This is a custom H-inspired investment navigation icon.
