local ADDON, NS = ...

-- Bootstrap NS.CharacterSheet so all subsequent CharacterSheet files can
-- rely on it existing.  Core.lua does the same idempotent guard.
NS.CharacterSheet = NS.CharacterSheet or {}
local CS = NS.CharacterSheet

CS.Utils = CS.Utils or {}
local Utils = CS.Utils

---------------------------------------------------------------------------
-- Shared guard helpers — extracted from the 5+ files that each defined
-- private identical copies.
--
-- Load order: this file must appear BEFORE Core.lua in the TOC so that
-- every sub-module can do `local Utils = CS.Utils` at the file top.
---------------------------------------------------------------------------

--- True when the account-currency-transfer UI is available (11.x+).
local _isAccountTransferBuild  -- cache (session-constant)

function Utils.IsAccountTransferBuild()
  if _isAccountTransferBuild == nil then
    _isAccountTransferBuild = (C_CurrencyInfo
      and type(C_CurrencyInfo.RequestCurrencyFromAccountCharacter) == "function") or false
  end
  return _isAccountTransferBuild
end

--- True when frame is shown (non-nil, has IsShown, and IsShown returns true).
function Utils.IsFrameVisible(frame)
  return frame and frame.IsShown and frame:IsShown()
end

--- True when the player is in combat lockdown.
function Utils.IsInLockdown()
  return InCombatLockdown and InCombatLockdown()
end

--- True when the current call stack is in a secure (taint-free) execution.
function Utils.IsSecureExecution()
  if type(issecure) ~= "function" then return false end
  local ok, secure = pcall(issecure)
  return ok and secure == true
end

--- Returns FrameFactory._state, or nil if FrameFactory is not yet loaded.
function Utils.GetFactoryState()
  local factory = CS and CS.FrameFactory or nil
  return factory and factory._state or nil
end
