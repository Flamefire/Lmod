require("strict")

local M   = {}
local Dbg = require("Dbg")
local MT  = require("MT")

local function shorten(name, level)
   if (level == 0) then
      return name
   end

   local i,j = name:find(".*/")
   j = (j or 0) - 1
   return name:sub(1,j)
end

function M.new(self, sType, name)
   local o = {}
   setmetatable(o,self)
   self.__index = self
   local mt = MT:mt()

   name          = (name or ""):gsub("/+$","")  -- remove any trailing '/'
   local sn      = false
   local version = false

   if (sType == "load") then
      for level = 0, 1 do
         local n = shorten(name, level)
         if (mt:locationTbl(n)) then
            sn = n
            break
         end
      end
   elseif(sType == "userName") then
      if (mt:exists(name)) then
         sn      = name
         name    = name
      else
         local n = shorten(name, 1)
         if (mt:exists(n) )then
            sn = n
         end
      end
   else
      for level = 0, 1 do
         local n = shorten(name, level)
         if (mt:exists(n)) then
            sn      = n
            version = mt:Version(sn)
            break
         end
      end
   end

   if (sn) then
      o._sn      = sn
      o._name    = name
      o._version = version or extractVersion(name, sn)
   end

   return o
end

function M.sn(self)
   return self._sn
end

function M.usrName(self)
   return self._name
end

function M.version(self)
   return self._version 
end

return M
