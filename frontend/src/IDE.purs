module IDE where

import Prelude

import Data.Const (Const)
import Data.Maybe (Maybe(..), isJust)
import Data.Either (Either(..))
import Data.Symbol (SProxy(..))
import Control.Monad.Loops (whileM_)
import Control.Monad.Rec.Class (forever)
import Effect.Class.Console as Console
import Effect.Aff as Aff
import Effect.Aff (Milliseconds(..))
import Effect.Aff.Class (class MonadAff)
import Effect.Exception (error)
import AceComponent as AceComponent
import Affjax as AX
import Affjax.StatusCode (StatusCode(..))
import Affjax.ResponseFormat as AXRF
import Affjax.RequestBody as AXRB
import Data.Argonaut (encodeJson, decodeJson, printJsonDecodeError)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Query.EventSource (EventSource)
import Halogen.Query.EventSource as EventSource
import Record as Record
import HTMLUtils as HU

type Slot = H.Slot (Const Void) Void

type LoginData =
   { botname :: String
   , password :: String
   }

type State
 = { loginData :: LoginData
   , editorCode :: String
   , testCode :: String
   , deployedCode :: String
   , loadingTest :: Boolean
   , testAgain :: Boolean
   , errorMessage :: Maybe String
   , memory :: String
   }

data Action
  = Initialize
  | Tick
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
    { initialState: \loginData ->
      { loginData
      , editorCode: ""
      , testCode: ""
      , deployedCode: ""
      , loadingTest: false
      , testAgain: false
      , errorMessage: Nothing
      , memory: ""
      }
    , render: render
    , eval: H.mkEval $ H.defaultEval {
        initialize = Just Initialize,
        handleAction = handleAction
      }
    }

render :: forall m. MonadAff m => State -> H.ComponentHTML Action ChildSlots m
render st =
  HH.section [HU.classes ["section"]]
  [ HU.divClass ["container"]
    [ HH.h1 [ HU.classes ["title"] ]
      [ HH.text ("This is the brain of " <> st.loginData.botname)
      ]
    , HU.divClass ["columns"]
      [ HU.divClass ["column","is-8"]
        [ HU.divClass ["card"]
          [ HU.divClass ["card-header"]
            [ HH.p [HU.classes ["card-header-title"]]
              [ HH.text "Code" ]
            ]
          , HU.divClass ["card-content"]
            [ HH.slot _ace unit AceComponent.component unit (Just <<< HandleAceUpdate)
            ]
          ]
        ]
      , HU.divClass ["column","is-4"]
        [ HU.divClass ["block"]
          [ HU.divClass ["card"]
            [ HU.divClass ["card-header"]
              [ HH.p [HU.classes ["card-header-title"]]
                [ HH.text "Status" ]
              ]
            , HU.divClass ["card-content"]
              [ HH.p_ $
                case st.errorMessage of
                  Nothing -> [ HH.text "All good! 👍" ]
                  Just err -> [ HH.text err ]
              ]
            , HU.divClass ["card-footer"]
              [ HH.button
                [ HU.classes ["card-footer-item button is-primary"]
                , HP.disabled (isJust st.errorMessage || st.deployedCode == st.editorCode)
                , HE.onClick \_ -> Just Deploy
                ]
                [ HH.text "Deploy" ]
              ]
            ]
          ]
        , HU.divClass ["block"]
          [ HU.divClass ["card"]
            [ HU.divClass ["card-header"]
              [ HH.p [HU.classes ["card-header-title"]]
                [ HH.text "Memory" ]
              ]
            , HU.divClass ["card-content"]
              [ HH.pre_ [ HH.text st.memory ]]
            ]
          ]
        , HU.divClass ["block"]
          [ HU.divClass ["card"]
            [ HU.divClass ["card-header"]
              [ HH.p [HU.classes ["card-header-title"]]
                [ HH.text "Log" ]
              ]
            , HU.divClass ["card-content"]
              [ HH.text "None yet!" ]
            ]
          ]
        ]
      ]
    ]
  ]


reallyUpdateTestStatus :: forall o m. MonadAff m => H.HalogenM State Action ChildSlots o m Unit
reallyUpdateTestStatus = do
  st <- H.get
  let req = Record.union st.loginData { new_code: st.editorCode }
  response_or_error <- H.liftAff $ AX.post AXRF.json "/api/test_code" (Just (AXRB.Json (encodeJson req)))
  case response_or_error of
    Left err -> Console.log (AX.printError err)
    Right response -> do
      if response.status == StatusCode 200
      then case decodeJson response.body of
        Left err -> Console.log (printJsonDecodeError err)
        Right ({error}::{error :: Maybe String}) -> do
          H.modify_ (_{errorMessage = error})
      else Console.log "status code not 200" -- (show response)

updateTestStatus :: forall o m. MonadAff m => H.HalogenM State Action ChildSlots o m Unit
updateTestStatus = do
  H.modify_ (_{testAgain = true})
  st <- H.get
  unless (st.loadingTest) $ do
    H.modify_ (_{loadingTest = true})
    whileM_ (H.gets (_.testAgain)) do
      H.modify_ (_{testAgain = false})
      reallyUpdateTestStatus
    H.modify_ (_{loadingTest = false})

handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action ChildSlots o m Unit
handleAction = case _ of
  Initialize -> do
    st <- H.get
    response_or_error <- H.liftAff $ AX.post AXRF.json "/api/get_code" (Just (AXRB.Json (encodeJson st.loginData)))
    case response_or_error of
      Left err -> Console.log (AX.printError err)
      Right response -> do
        if response.status == StatusCode 200
        then case decodeJson response.body of
          Left err -> Console.log (printJsonDecodeError err)
          Right ({code}::{code :: String}) -> do
            void $ H.query _ace unit $ H.tell (AceComponent.InitText code)
            H.modify_ (_
              { testCode = code
              , editorCode = code
              , deployedCode = code
              })
        else Console.log "status code not 200" -- (show response)
    _ <- H.subscribe timer
    pure unit

  Tick -> do
    st <- H.get
    response_or_error <- H.liftAff $ AX.post AXRF.json "/api/get_state" (Just (AXRB.Json (encodeJson st.loginData)))
    case response_or_error of
      Left err -> Console.log (AX.printError err)
      Right response -> do
        if response.status == StatusCode 200
        then case decodeJson response.body of
          Left err -> Console.log (printJsonDecodeError err)
          Right ({state}::{state :: String}) -> do
            H.modify_ (_ { memory = state })
        else Console.log "status code not 200" -- (show response)

  Deploy -> do
    st <- H.get
    unless (st.loadingTest) $ do
      H.modify_ (_{ deployedCode = st.editorCode })
      let req = Record.union st.loginData { new_code: st.editorCode }
      response_or_error <- H.liftAff $ AX.post AXRF.json "/api/set_code" (Just (AXRB.Json (encodeJson req)))
      case response_or_error of
        Left err -> Console.log (AX.printError err)
        Right response -> do
          if response.status == StatusCode 200
          then case decodeJson response.body of
            Left err -> Console.log (printJsonDecodeError err)
            Right ({}::{}) -> do
              pure unit
          else Console.log "status code not 200" -- (show response)

  HandleAceUpdate (AceComponent.TextChanged code) -> do
    H.modify_ (_{ editorCode = code })
    updateTestStatus

timer :: forall m. MonadAff m => EventSource m Action
timer = EventSource.affEventSource \emitter -> do
  fiber <- Aff.forkAff $ forever do
    Aff.delay $ Milliseconds 1000.0
    EventSource.emit emitter Tick

  pure $ EventSource.Finalizer do
    Aff.killFiber (error "Event source finalized") fiber
