-- ServerAdmin loader
ServerAdmin = ServerAdmin or {}
ServerAdmin.Version = "3.2.0"

if SERVER then
    AddCSLuaFile("serveradmin/cl_menu.lua")
    include("serveradmin/sv_core.lua")
    include("serveradmin/sv_ulx.lua")
else
    include("serveradmin/cl_menu.lua")
end
