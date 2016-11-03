require("strict")
require("declare")
require("utils")
_G._DEBUG       = false
local M         = {}
local MRC       = require("MRC")
local dbg       = require("Dbg"):dbg()
local lfs       = require("lfs")
local open      = io.open
local posix     = require("posix")

local access    = posix.access
local concatTbl = table.concat
local readlink  = posix.readlink
local stat      = posix.stat

local ignoreT = {
   ['.']         = true,
   ['..']        = true,
   ['.git']      = true,
   ['.svn']      = true,
   ['.lua']      = true,
   ['.DS_Store'] = true,
}

local function keepFile(fn)
   local firstChar = fn:sub(1,1)
   local lastChar  = fn:sub(-1,-1)
   local firstTwo  = fn:sub(1,2)

   local result    = not (ignoreT[fn]     or lastChar == '~' or firstChar == '#' or 
                          lastChar == '#' or firstTwo == '.#')
   if (not result) then
      return false
   end

   if (firstChar == "." and fn:sub(-4,-1) == ".swp") then
      return false
   end

   return true
end

local defaultFnT = {
   default       = 1,
   ['.modulerc'] = 2,
   ['.version']  = 3,
}

local function checkValidModulefileReal(fn)
   local f = open(fn,"r")
   if (not f) then
      return false
   end
   local line = f:read(20) or ""
   f:close()

   return line:find("^#%%Module")
end

local function checkValidModulefileFake(fn)
   return true
end

local checkValidModulefile = checkValidModulefileReal

--------------------------------------------------------------------------
-- Use readlink to find the link
-- @param path the path to the module file.
local function walk_link(path)
   local attr   = lfs.symlinkattributes(path)
   if (attr == nil) then
      return nil
   end

   if (attr.mode == "link") then
      local rl = readlink(path)
      if (not rl) then
         return nil
      end
      return pathJoin(dirname(path),rl)
   end
   return path
end

--------------------------------------------------------------------------
-- This routine is given the absolute path to a .version
-- file.  It checks to make sure that it is a valid TCL
-- file.  It then uses the ModulesVersion.tcl script to
-- @param defaultT - A table containing: { fullName=, fn=, mpath=, luaExt=, barefn=}

-- return what the value of "ModulesVersion" is.
local function versionFile(mrc, defaultT)
   local path = defaultT.fn
   
   if (defaultT.barefn == "default") then
      defaultT.value = barefilename(walk_link(defaultT.fn)):gsub("%.lua$","")
      return defaultT
   end

   if (not checkValidModulefile(path)) then
      return defaultT
   end

   local version = false
   local whole
   local status
   local func
   local optStr  = ""
   whole, status = runTCLprog("RC2lua.tcl", optStr, path)
   if (not status) then
      LmodError("Unable to parse: ",path," Aborting!\n")
   end

   declare("modA",{})
   status, func = pcall(load, whole)
   if (not status or not func) then
      LmodError("Unable to parse: ",path," Aborting!\n")
   end
   func()

   local _, _, name = defaultT.fullName:find("(.*)/.*")

   defaultT.value = mrc:parseModA_for_moduleA(name,modA)

   return defaultT
end


local function walk(mrc, mpath, path, dirA, fileT)
   local defaultIdx = 1000000
   local defaultT   = {}

   for f in lfs.dir(path) do
      repeat
         local file = pathJoin(path, f)
         if (not keepFile(f)) then break end

         local attr = (f == "default") and lfs.symlinkattributes(file) or lfs.attributes(file) 
         if (attr == nil or (attr.uid == 0 and not attr.permissions:find("......r.."))) then break end
         local mode = attr.mode
         
         if (mode == "directory" and f ~= "." and f ~= "..") then
            dirA[#dirA + 1 ] = file
         elseif (mode == "file" or mode == "link") then
            local dfltFound = defaultFnT[f]
            local idx       = dfltFound or defaultIdx
            local fullName  = extractFullName(mpath, file)
            if (dfltFound) then
               if (idx < defaultIdx) then
                  defaultIdx = idx
                  local luaExt = f:find("%.lua$")
                  defaultT     = { fullName = fullName, fn = file, mpath = mpath, luaExt = luaExt, barefn = f}
               end
            elseif (not fileT[fullName] or not fileT[fullName].luaExt) then
               local luaExt = f:find("%.lua$")
               if (accept_fn(file) and (luaExt or checkValidModulefile(file))) then
                  fileT[fullName] = {fn = file, canonical = f:gsub("%.lua$", ""), mpath = mpath,
                                 luaExt = luaExt}
               end
            end
         end
      until true
   end
   if (next(defaultT) ~= nil) then
      defaultT = versionFile(mrc, defaultT)
   end

   return defaultT
end

local function walk_tree(mrc, mpath, pathIn, dirT)

   local dirA     = {}
   local fileT    = {}
   local defaultT = walk(mrc, mpath, pathIn, dirA, fileT)

   dirT.fileT    = fileT
   dirT.defaultT = defaultT
   dirT.dirT     = {}

   for i = 1,#dirA do
      local path     = dirA[i]
      local fullName = extractFullName(mpath, path)
      
      dirT.dirT[fullName] = {}
      walk_tree(mrc, mpath, path, dirT.dirT[fullName])
   end

end

local function build(mpathA)
   local dirA = {}
   local mrc  = MRC:singleton()

   for i = 1,#mpathA do
      local mpath = mpathA[i]
      if (isDir(mpath)) then
         local dirT  = {}
         walk_tree(mrc, mpath, mpath, dirT)
         dirA[#dirA+1] = {mpath=mpath, dirT=dirT}
      end
   end
      
   return dirA

end

function M.new(self, mpathA)
   local o = {}
   setmetatable(o,self)
   self.__index = self
   self.__dirA  = build(mpathA)
   return o
end

function M.dirA(self)
   return self.__dirA
end

return M