-- ServerAdmin loader
ServerAdmin = ServerAdmin or {}
ServerAdmin.Version = "2.0.0"

if SERVER then
    AddCSLuaFile("serveradmin/cl_menu.lua")
    include("serveradmin/sv_core.lua")
else
    include("serveradmin/cl_menu.lua")
end
