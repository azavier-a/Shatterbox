
# Shatterbox Client-Server Voxel Destruction

Reference manual (extreme WIP): https://shatterbox.xyz/

Discord: https://discord.gg/WRfz79uRTy

DevForum Thread: https://devforum.roblox.com/t/shatterbox-client-server-voxel-destruction-simple-and-optimized-release-77/3674163?u=azavier123


Shatterbox is a voxel destruction library that aims for insane performance as well as ease of use.



Installation:

1. Place `Shatterbox` package as a descendant of `ReplicatedStorage`.

2. Require the `Shatterbox.Main` module at *server initialization* to properly initialize client-server features.

IF YOU DON'T USE BLINK YOU ARE DONE.

These steps ensure events are properly batched using Blink, saving performance.
I don't think anything bad happens if you don't set up batching using these steps.

ROBLOX STUDIO {

    3. Run the command at the top of `Shatterbox.Main` to populate the "Shatterbox" blink configuration

    4. Import the "Shatterbox.blink" file at the top of your Blink config:		import "Shatterbox"

	5. Rebuild your blink files

	6. Re-define PathToServer and PathToClient local variables defined above to the location of your blink files
}

VISUAL STUDIO CODE {

    3. Import the "Shatterbox.blink" file at the top of your Blink config:		import "PATH_TO_SHATTERBOX/Shatterbox.blink"

    4. Rebuild your blink files

    5. Re-define PathToServer and PathToClient local variables defined above to the location of your blink files
}