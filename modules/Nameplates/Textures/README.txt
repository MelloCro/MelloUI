SimpleNameplates Texture Files
==============================

This folder should contain texture files in .tga or .blp format for use with the addon.

Recommended texture specifications:
- Format: TGA (32-bit) or BLP
- Dimensions: 256x32 pixels (or any power of 2)
- Alpha channel: Optional (for transparency effects)

Default textures referenced in the addon:
1. Aluminium.tga - A brushed aluminum look
2. BantoBar.tga - A clean modern bar
3. Smooth.tga - A smooth gradient bar
4. Perl.tga - Classic Perl UI style
5. Gloss.tga - Glossy/shiny appearance
6. Charcoal.tga - Dark charcoal texture
7. Minimalist.tga - Simple flat color

To add custom textures:
1. Place your .tga or .blp file in this folder
2. Edit SimpleNameplates.lua and add your texture to the textures table
3. Reload the UI with /reload

Example texture path format:
"Interface\\AddOns\\SimpleNameplates\\Textures\\YourTextureName"