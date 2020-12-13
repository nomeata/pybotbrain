module HTMLUtils where

import Prelude

import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

classes :: forall a b. Array String -> HP.IProp (class :: String | a) b
classes cs = HP.classes (map HH.ClassName cs)

divClass :: forall a b. Array String -> Array (HH.HTML a b) -> HH.HTML a b
divClass cs = HH.div [ classes cs]

fullHeight :: forall a b . HH.HTML a b -> HH.HTML a b
fullHeight body =
  HH.section
    [ classes ["hero","is-fullheight"] ]
    [ divClass ["hero-body"] [body] ]
