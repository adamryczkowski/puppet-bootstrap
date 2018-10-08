enabled1 = true

return {
--Shard Configuration Mod OK
--##################
  ["workshop-595764362"] = {
    enabled = true,
    configuration_options = {
      ["DeleteUnused"] = true,
      ["SyncFromMaster"] = true,
      ["Connections"] = { -- this must be same in every shard
        ["1"] = { "11", "11", "11", "11", "11", "11", "11"}, -- I want 2 connections between world "1" and "12"
        ["11"] = { "12", "12", "12", "12"},
        ["12"] = { "13", "13", "13", "13" } -- return connection between worlds "12" and "1" is not needed, mod is taking care of that
      }
    }
  }
}
