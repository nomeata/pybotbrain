module Container where

import Prelude
import Data.Maybe (Maybe(..))
import Data.Symbol (SProxy(..))
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage as Storage

import Login as Login
import IDE as IDE

data State = Login | IDE Login.LoginData

-- | The query algebra for the app.
data Action
  = HandleLogin Login.LoginData
  | HandleLogout IDE.Output

type ChildSlots =
  ( login :: Login.Slot Unit
  , ide   :: IDE.Slot Unit
  )

_login = SProxy :: SProxy "login"
_ide = SProxy :: SProxy "ide"

-- | The main UI component definition.
component :: forall f i o m. MonadAff m => H.Component HH.HTML f i o m
component =
  H.mkComponent
    { initialState: \_ -> Login
    , render: render
    , eval: H.mkEval $ H.defaultEval { handleAction = handleAction }
    }

render :: forall m. MonadAff m => State -> H.ComponentHTML Action ChildSlots m
render Login =
  HH.slot _login unit Login.component unit (Just <<< HandleLogin)
render (IDE loginData) =
  HH.slot _ide unit IDE.component loginData (Just <<< HandleLogout)

handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action ChildSlots o m Unit
handleAction = case _ of
  HandleLogin loginData -> H.put (IDE loginData)
  HandleLogout IDE.Logout -> do
    -- A slight break of abstraction; this should happen in the Login component
    pw <- H.liftEffect $ do
      w <- window
      s <- localStorage w
      Storage.removeItem "token" s
    H.put Login
