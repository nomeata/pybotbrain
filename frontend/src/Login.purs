module Login where

import Prelude

import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Foldable (foldMap)
import Effect.Aff.Class (class MonadAff)
import Affjax as AX
import Affjax.StatusCode (StatusCode(..))
import Affjax.ResponseFormat as AXRF
import Affjax.RequestBody as AXRB
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.HTML.Events as HE
-- import Debug.Trace as Debug
import Data.Argonaut (encodeJson, decodeJson, printJsonDecodeError)

type Slot = H.Slot (Const Void) LoginData

type LoginData =
   { botname :: String
   , password :: String
   }

type State =
   { botname :: String
   , password :: String
   , loading :: Boolean
   , lastError :: Maybe String
   }

data LoginAction
  = ChangeBotname String
  | ChangePassword String
  | DoLogin

component :: forall f i m. MonadAff m => H.Component HH.HTML f i LoginData m
component =
  H.mkComponent
    { initialState: \_ -> {
        botname : "EllasTestBot",
        password: "XMWBTB",
        lastError: Nothing,
        loading: false
      }
    , render: renderLogin
    , eval: H.mkEval $ H.defaultEval { handleAction = handleLoginAction }
    }

renderLogin :: forall m. MonadAff m => State -> H.ComponentHTML LoginAction () m
renderLogin st =
  HH.div_
    [ HH.h1_
        [ HH.text "Login" ]
    , HH.div_
        [ HH.p_ $
          [ HH.input [ HP.name "botname", HP.value st.botname, HE.onValueInput (Just <<< ChangeBotname) ]
          , HH.input [ HP.name "pw", HP.type_ HP.InputPassword, HP.value st.password, HE.onValueInput (Just <<< ChangePassword)  ]
          , HH.button
            [ HP.disabled st.loading
            , HE.onClick \_ -> Just DoLogin ]
            [ HH.text "Login" ]
          ] <> (foldMap (\err -> [ HH.p_ [ HH.text err] ]) st.lastError )
        ]
    ]

handleLoginAction :: forall m.  MonadAff m => LoginAction -> H.HalogenM State LoginAction () LoginData m Unit
handleLoginAction = case _ of
  ChangeBotname s -> H.modify_ (_ { botname = s})
  ChangePassword s -> H.modify_ (_ { password = s})
  DoLogin -> do
    {botname, password} <- H.get

    -- H.liftEffect $ Event.preventDefault event
    H.modify_ (_ { loading = true })
    response_or_error <- H.liftAff $ AX.post AXRF.json "http://localhost:5000/api/login" (Just (AXRB.Json (encodeJson {botname, password})))
    H.modify_ (_ { loading = false} )
    case response_or_error of
      Left err -> H.modify_ (_ {lastError = Just (AX.printError err) })
      Right response -> do
        if response.status == StatusCode 200
        then H.raise {botname, password}
        else case decodeJson response.body of
          Left err -> H.modify_ (_ {lastError = Just (printJsonDecodeError err) })
          Right ({error}::{error :: String}) -> H.modify_ (_ {lastError = Just error })
