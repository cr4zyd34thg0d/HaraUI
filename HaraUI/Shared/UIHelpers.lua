local ADDON, NS = ...

NS.UIHelpers = NS.UIHelpers or {}

function NS.UIHelpers.Clamp(v, minv, maxv)
  if v < minv then return minv end
  if v > maxv then return maxv end
  return v
end
