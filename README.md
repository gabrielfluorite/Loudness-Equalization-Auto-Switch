This is a simple PowerShell script that toggles the Loudness Equalization option in Windows audio settings between ON and OFF.

The script only works if your audio driver ***already includes*** the Loudness Equalizatoin option in there. You can verify by pressing Win + R, typing mmsys.cpl, double-clicking your audio playback device, and navigating to the Enhancements tab.

I **HIGHLY SUGGEST** that you first set the Loudness Equalization **"Release Time"** option to ***Short*** in the "Settings..." button just above "Preview" while Loudness Equalization is highlighted.

Download the .zip file, extract it and keep both .ps1 and .cmd files together in the same folder. Simply double-click the .cmd file in order to run the script (it calls for the .ps1 file, which contains the script itself). You can create a shortcut of the .cmd file to your desktop and rename it if you wish.

**DO NOT CHANGE THE .ps1 FILE NAME.**
**KEEP BOTH FILES TOGETHER IN THE SAME FOLDER**

*Made with Codex.*
