module IDE where

import Prelude

import Data.Const (Const)
import Data.Foldable (foldMap)
import Data.Maybe (Maybe(..), isNothing)
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
import Web.Event.Event as Event
import Web.Event.Event (Event)
import Record as Record
import HTMLUtils as HU

type Slot = H.Slot (Const Void) Output

type LoginData =
   { botname :: String
   , password :: String
   }

data Output
 = Logout

type State
 = { loginData :: LoginData
   , editorCode :: String
   , testCode :: String
   , deployedCode :: String
   , loadingTest :: Boolean
   , testAgain :: Boolean
   , errorMessage :: Maybe String
   , memory :: String
   , evaling :: Boolean
   , eval_code :: String
   , eval_message :: Maybe String
   }

data Action
  = Initialize
  | ReloadMemory
  | Deploy
  | DoEval Event
  | ChangeEvalCode String
  | HandleAceUpdate AceComponent.Output
  | DoLogout

type ChildSlots =
  ( ace :: AceComponent.Slot Unit
  )

_ace = SProxy :: SProxy "ace"

-- | The main UI component definition.
component :: forall f m. MonadAff m => H.Component HH.HTML f LoginData Output m
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
      , evaling: false
      , eval_code: ""
      , eval_message: Nothing
      } :: State
    , render: render
    , eval: H.mkEval $ H.defaultEval {
        initialize = Just Initialize,
        handleAction = handleAction
      }
    }

render :: forall m. MonadAff m => State -> H.ComponentHTML Action ChildSlots m
render st =
  HH.section [HU.classes ["section"]]
  [ HU.divClass []
    [ HH.h1 [ HU.classes ["title"] ]
      [ HH.text ("This is the brain of " <> st.loginData.botname) ]
    , HU.divClass ["columns"]
      [ HU.divClass ["column","is-7"]
        [ HU.divClass ["card"]
          [ HU.divClass ["card-header"]
            [ HH.p [HU.classes ["card-header-title"]]
              [ HH.text "Code" ]
            ]
          , HH.slot _ace unit AceComponent.component unit (Just <<< HandleAceUpdate)
          ]
        ]
      , HU.divClass ["column","is-5"]
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
              [ let enabled = isNothing st.errorMessage && st.deployedCode /= st.editorCode in
                HH.button
                [ HU.classes (["card-footer-item", "button"] <> (if enabled then ["is-primary"] else []))
                , HP.disabled (not enabled)
                , HE.onClick \_ -> Just Deploy
                ]
                [ HH.text "Deploy" ]
              , HH.button
                [ HU.classes ["card-footer-item", "button", "is-dark"]
                , HE.onClick \_ -> Just DoLogout
                ]
                [ HH.text "Logout" ]
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
              [ HH.pre [ HU.classes ["p-0"]] [ HH.text st.memory ] ]
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
        , HU.divClass ["block"]
          [ HU.divClass ["card"]
            [ HU.divClass ["card-header"]
              [ HH.p [HU.classes ["card-header-title"]]
                [ HH.text "Eval" ]
              ]
            , HU.divClass ["card-content"] $
              [ HH.form
                [ HU.classes ["block"]
                , HE.onSubmit \e -> Just (DoEval e) ] $
                [ HU.divClass ["field has-addons"]
                  [ HU.divClass ["control is-expanded"]
                    [ HH.input
                      [ HU.classes ["input is-fullwidth"]
                      , HP.name "eval-code"
                      , HP.value st.eval_code
                      , HE.onValueInput (Just <<< ChangeEvalCode)
                      , HP.placeholder "private_message('Peter','Hallo!')"
                      ]
                    ]
                  , HU.divClass (["control"] <> (if st.evaling then ["is-loading"] else []))
                    [ let enabled = st.eval_code /= "" && not st.evaling && isNothing st.errorMessage in
                      HH.button
                      [ HP.disabled (not enabled)
                      , HU.classes $ ["button"] <> (if enabled then ["is-primary"] else [])
                      ]
                      [ HH.text "Run" ]
                    ]
                  ]
                ]
              ] <>
              foldMap (\msg -> [
                HU.divClass ["block"]
                [ if msg == ""
                  then HH.p [ HU.classes ["has-text-centered"] ] [ HH.text "– no output –" ]
                  else HH.pre [ HU.classes ["p-0"] ] [ HH.text msg ]
                ]
              ]) st.eval_message
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

handleAction :: forall m. MonadAff m => Action -> H.HalogenM State Action ChildSlots Output m Unit
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
    handleAction ReloadMemory
    _ <- H.subscribe timer
    pure unit

  ReloadMemory -> do
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

  DoLogout -> do
    H.raise Logout

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

  ChangeEvalCode s -> H.modify_ (_ { eval_code = s})

  DoEval event -> do
    H.liftEffect $ Event.preventDefault event
    st <- H.get
    unless st.evaling $ do
      H.modify_ (_{evaling = true, eval_message = Nothing })
      let req = Record.union st.loginData { mod_code: st.editorCode, eval_code: st.eval_code }
      response_or_error <- H.liftAff $ AX.post AXRF.json "/api/eval_code" (Just (AXRB.Json (encodeJson req)))
      case response_or_error of
        Left err -> Console.log (AX.printError err)
        Right response -> do
          if response.status == StatusCode 200
          then case decodeJson response.body of
            Left err -> Console.log (printJsonDecodeError err)
            Right ({output}::{output :: String}) -> do
              H.modify_ (_ { eval_message = Just output })
              handleAction ReloadMemory
          else Console.log "status code not 200" -- (show response)
      H.modify_ (_{evaling = false})

  HandleAceUpdate (AceComponent.TextChanged code) -> do
    H.modify_ (_{ editorCode = code })
    updateTestStatus

timer :: forall m. MonadAff m => EventSource m Action
timer = EventSource.affEventSource \emitter -> do
  fiber <- Aff.forkAff $ forever do
    Aff.delay $ Milliseconds 10000.0
    EventSource.emit emitter ReloadMemory

  pure $ EventSource.Finalizer do
    Aff.killFiber (error "Event source finalized") fiber
