# MCBE Tweaks

## **Disable V-Sync**
go to  *%LOCALAPPDATA%\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang\minecraftpe\options.txt*
and set **gfx_vsync** to 0.

## **Optimise In-Game Settings**
**FULLSCREEN: ON** - *windowed mode causes HUGE input lag.*

**HIDE PAPER DOLL: ON** - *This hides the render of your skin in the corner of the screen, saving a small bit of performance.*

**SCREEN ANIMATIONS: OFF** - *this will remove the animation when opening various gui elements.*

**SCREEN SAFE AREA:** *set this to 100% for everything to fit properly, Make this value smaller if you want to make the gui alot smaller.*

**VIEW BOBBING: OFF** - *Bedrock's View Bobbing sucks.*

**FANCY LEAVES:** *Turn this off for slightly more frames, at the expense of looks.*

**BEAUTIFUL SKIES: ON** - *This barely affects performance and you need it to see the custom skyboxes.*

**SMOOTH LIGHTING: ON** - *This barely affects performance and if you do turn it off, you will need fullbright in order for it to not look terrible.*

**FANCY GRAPHICS: ON** - *This has negligible impact on performance and it will make entities look extremely flat and 2D when off, won't reccomend.*

**DYNAMIC FOV:** *depends on the gamemode you use, if you use very high fov, speed will cause alot of distortion. I keep it on for the visual feedback when sprinting.*

**GUI SCALE: -1** - *This is the lowest you can go and any larger looks horrendous.*

**RENDER DISTANCE:** **16** - **12** *for high and mid pc's, 8 for low end machines. Due to how bedrock works, having tiny renderdistance barely improves performance and can sometimes make it worse due to unbalanced load on the CPU and GPU.*

## **Improve Bedrock graphics**

- [cleanhud](https://mcpedl.com/clean-hud-pack)
- [Java Animations](https://mcpedl.com/java-1-7-animations)
- [Fog Remover Shader](https://github.com/Furzide/RenderDragonFogRemover)

## **Fix Performance on RTX GPUs**
download and run **Nvidia Profile Inspector** or later  
search and open the profile for **Minecraft**  
scroll down until you see the **"Raytracing - (DXR) Enabled"** setting. Set this to **RT Disabled.**  
