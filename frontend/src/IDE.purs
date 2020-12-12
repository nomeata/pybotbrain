module IDE where

import Prelude

import Data.Const (Const)
import Data.Maybe (Maybe(..))
import Data.Either (Either(..))
import Data.Symbol (SProxy(..))
import Effect.Class.Console as Console
import Effect.Aff.Class (class MonadAff)
import AceComponent as AceComponent
import Affjax as AX
import Affjax.StatusCode (StatusCode(..))
import Affjax.ResponseFormat as AXRF
import Affjax.RequestBody as AXRB
import Data.Argonaut (encodeJson, decodeJson, printJsonDecodeError)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Record as Record

type Slot = H.Slot (Const Void) Void

type LoginData =
   { botname :: String
   , password :: String
   }

type State
 = { loginData :: LoginData
   , code :: String
   }

data Action
  = Initialize
  | Deploy
  | HandleAceUpdate AceComponent.Output

type ChildSlots =
  ( ace :: AceComponent.Slot Unit
  )

_ace = SProxy :: SProxy "ace"

-- | The main UI component definition.
component :: forall f o m. MonadAff m => H.Component HH.HTML f LoginData o m
component =
  H.mkComponent
    { initialState: \loginData -> { loginData, code: "" }
    , render: render
    , eval: H.mkEval $ H.defaultEval {
        initialize = Just Initialize,
        handleAction = handleAction
      }
    }

render :: forall m. MonadAff m => State -> H.ComponentHTML Action ChildSlots m
render ({ code: code }) =
  HH.div_
    [ HH.h1_
        [ HH.text "ace editor" ]
    , HH.div_
        [ HH.p_
            [ HH.button
                [ HE.onClick \_ -> Just Deploy ]
                [ HH.text "Deploy" ]
            ]
        ]
    , HH.div_
        [ HH.slot _ace unit AceComponent.component unit (Just <<< HandleAceUpdate) ]
    , HH.p_
        [ HH.text ("Current text: " <> code) ]
    ]

handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action ChildSlots o m Unit
handleAction = case _ of
  Initialize -> do
    st <- H.get
    response_or_error <- H.liftAff $ AX.post AXRF.json "http://localhost:5000/api/get_code" (Just (AXRB.Json (encodeJson st.loginData)))
    case response_or_error of
      Left err -> Console.log (AX.printError err)
      Right response -> do
        if response.status == StatusCode 200
        then case decodeJson response.body of
          Left err -> Console.log (printJsonDecodeError err)
          Right ({code}::{code :: String}) -> do
            void $ H.query _ace unit $ H.tell (AceComponent.ChangeText code)
            H.modify_ (_ {code = code })
        else Console.log "status code not 200" -- (show response)

  Deploy -> do
    st <- H.get
    let req = Record.union st.loginData { new_code: st.code }
    response_or_error <- H.liftAff $ AX.post AXRF.json "http://localhost:5000/api/set_code" (Just (AXRB.Json (encodeJson req)))
    case response_or_error of
      Left err -> Console.log (AX.printError err)
      Right response -> do
        if response.status == StatusCode 200
        then case decodeJson response.body of
          Left err -> Console.log (printJsonDecodeError err)
          Right ({}::{}) -> do
            pure unit
        else Console.log "status code not 200" -- (show response)
  HandleAceUpdate msg ->
    handleAceOuput msg

handleAceOuput :: forall o m. MonadAff m => AceComponent.Output -> H.HalogenM State Action ChildSlots o m Unit
handleAceOuput = case _ of
  AceComponent.TextChanged code -> H.modify_ (_{ code = code })
