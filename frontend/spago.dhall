{ name = "halogen-project"
, dependencies =
  [ "ace"
  , "affjax"
  , "argonaut"
  , "argonaut-codecs"
  , "console"
  , "debug"
  , "effect"
  , "halogen"
  , "psci-support"
  , "record"
  ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs" ]
}
