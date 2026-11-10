# Shoreline 应用图标

使用内置 image_gen 工具生成，2026-11-10。原始 PNG 保存在 AppIcon.icon/Assets/source.png，保留透明背景。Icon Composer 配置用于新系统的原生图标呈现，scripts/build-icon.sh 通过 Apple actool 生成 Assets.car 与兼容图标 AppIcon.icns。

图层缩放设为 1.1，让画面延伸到系统圆角矩形遮罩之外，覆盖背景底色。

## 生成提示词

```text
Use case: logo-brand.
Asset type: one finished macOS application icon for Shoreline, a local adaptive animated desktop wallpaper app with beach and meadow themes.
Create a distinctive, beautifully polished coastal island icon. A single macOS rounded-square tile is centered on a 1024 by 1024 transparent canvas, occupying about 82% of the canvas width with generous equal transparent margins. Within the tile, turquoise and deep teal ocean water surrounds a bold sweeping ivory-sand shoreline and a simple fresh sage-green island. The coastline gently curls around one small pearl-white rounded-square pebble, subtly evoking a desktop icon protected by the landscape. Use a top-down, lightly sculpted illustration with refined soft depth, rounded edges, a delicate sunlit highlight, and restrained soft shadow. Calm, warm, modern and tactile, with a strong silhouette that reads clearly at 32 pixels. Make the coastline the dominant recognisable shape and keep the composition balanced and simple.
No lettering, no text, no watermark, no interface mockup, no perspective-tilted tile, no tiny scenery, no palm trees, no extra objects, no surrounding background. The space outside the single rounded-square tile must be genuinely transparent. Deliver the icon itself, square, high resolution.
```
