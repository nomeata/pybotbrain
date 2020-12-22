module IDE where

import Prelude

import Data.Const (Const)
import Data.Foldable (foldMap, null, for_)
import Data.Maybe (Maybe(..), maybe)
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
import Affjax.RequestHeader as AXRH
import Data.HTTP.Method (Method(POST))
import Data.Argonaut (class EncodeJson, class DecodeJson, encodeJson, decodeJson, printJsonDecodeError, getField, getFieldOptional)
import Data.Argonaut.Parser (jsonParser)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Query.EventSource (EventSource)
import Halogen.Query.EventSource as EventSource
import Web.Event.Event as Event
import Web.Event.Event (Event)
import HTMLUtils as HU

type Slot = H.Slot (Const Void) Output

type LoginData = { token :: String }

data Output
 = Logout

data ErrorMessage
 = Checking
 | AllGood
 | Error String

derive instance eqErrorMessage :: Eq ErrorMessage

type State
 = { loginData :: LoginData
   , botname :: String
   , editorCode :: String
   , testCode :: String
   , deployedCode :: String
   , loadingTest :: Boolean
   , testAgain :: Boolean
   , errorMessage :: ErrorMessage
   , memory :: String
   , events :: Array LogEvent
   , evaling :: Boolean
   , eval_code :: String
   , eval_message :: Maybe String
   }

data Action
  = Initialize
  | ReloadMemory
  | Deploy
  | Revert
  | DoEval Event
  | ChangeEvalCode String
  | HandleAceUpdate AceComponent.Output
  | DoLogout

type ChildSlots =
  ( ace :: AceComponent.Slot Unit
  )

_ace = SProxy :: SProxy "ace"

data LogEvent
  = EvalEvent { exception :: Maybe String }
  | MessageEvent { trigger :: String, from :: String, text :: String, response :: Maybe String, exception :: Maybe String }
  | OtherEvent

instance encodeLogEvent :: DecodeJson LogEvent where
    decodeJson json = do
       obj <- decodeJson json
       trigger <- getField obj "trigger"
       case trigger of
         "eval" -> do
            exception <- getFieldOptional obj "exception"
            pure $ EvalEvent {exception}
         "private" -> do
            from <- getField obj "from"
            text <- getField obj "text"
            response <- getFieldOptional obj "response"
            exception <- getFieldOptional obj "exception"
            pure $ MessageEvent { trigger, from, text, response, exception }
         "group" -> do
            from <- getField obj "from"
            text <- getField obj "text"
            response <- getFieldOptional obj "response"
            exception <- getFieldOptional obj "exception"
            pure $ MessageEvent { trigger, from, text, response, exception }
         _ -> pure OtherEvent

-- | The main UI component definition.
component :: forall f m. MonadAff m => H.Component HH.HTML f LoginData Output m
component =
  H.mkComponent
    { initialState: \loginData ->
      { loginData
      , botname: "…"
      , editorCode: ""
      , testCode: ""
      , deployedCode: ""
      , loadingTest: false
      , testAgain: false
      , errorMessage: AllGood
      , memory: ""
      , events: []
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
      [ HH.text ("This is the brain of " <> st.botname) ]
    , HU.divClass ["columns"]
      [ HU.divClass ["column","is-7"]
        [ HU.divClass ["card"]
          [ HU.divClass ["card-header"]
            [ HH.p [HU.classes ["card-header-title"]]
              [ HH.text "⌨️ Code" ]
            ]
          , HH.slot _ace unit AceComponent.component unit (Just <<< HandleAceUpdate)
          ]
        ]
      , HU.divClass ["column","is-5"]
        [ HU.divClass ["block"]
          [ HU.divClass ["card"]
            [ HU.divClass ["card-header"]
              [ HH.p [HU.classes ["card-header-title"]]
                [ HH.text "🚦 Status" ]
              ]
            , HU.divClass ["card-content"]
              [ HH.p_ $
                case st.errorMessage of
                  AllGood -> [ HH.text "😊 All good!" ]
                  Checking -> [ HH.text "🤔 Checking!" ]
                  Error err -> [ HH.text ("😬 " <> err) ]
              ]
            , HU.divClass ["card-footer"]
              [ let enabled = st.errorMessage == AllGood && st.deployedCode /= st.editorCode in
                HH.button
                [ HU.classes (["card-footer-item", "button"] <> (if enabled then ["is-primary"] else ["is-black"]))
                , HP.disabled (not enabled)
                , HE.onClick \_ -> Just Deploy
                ]
                [ HH.text "🚀 Deploy" ]
              , let enabled = st.deployedCode /= st.editorCode in
                HH.button
                [ HU.classes (["card-footer-item", "button"] <> (if enabled then ["is-dark"] else ["is-black"]))
                , HP.disabled (not enabled)
                , HE.onClick \_ -> Just Revert
                ]
                [ HH.text "♻️ Revert" ]
              , HH.button
                [ HU.classes ["card-footer-item", "button", "is-dark"]
                , HE.onClick \_ -> Just DoLogout
                ]
                [ HH.text "🚪 Logout" ]
              ]
            ]
          ]
        , HU.divClass ["block"]
          [ HU.divClass ["card"]
            [ HU.divClass ["card-header"]
              [ HH.p [HU.classes ["card-header-title"]]
                [ HH.text "🧠 Memory" ]
              ]
            , HU.divClass ["card-content"]
              [ HH.pre [ HU.classes ["p-0"]] [ HH.text st.memory ] ]
            ]
          ]
        , HU.divClass ["block"]
          [ HU.divClass ["card"]
            [ HU.divClass ["card-header"]
              [ HH.p [HU.classes ["card-header-title"]]
                [ HH.text "📓 Log" ]
              ]
            , HU.divClass ["card-content"] $
              if null st.events
              then [ HH.text "None yet!" ]
              else foldMap (case _ of
                  OtherEvent -> []
                  EvalEvent e ->
                    [ HH.p_ [ HH.text "🔬 Eval" ]] <>
                    foldMap (\s -> [ HH.p_ [ HH.text $ "😬 " <> s ]]) e.exception
                  MessageEvent e ->
                    [ HH.p_ [ HH.text $ "⬅️ " <> e.from <> ": " <> e.text ]] <>
                    foldMap (\s ->
                      [ HH.p_ [ HH.text $ "➡️ " <> st.botname <> ": " <> s ]]
                    ) e.response <>
                    foldMap (\s -> [ HH.p_ [ HH.text $ "😬 " <> s ]]) e.exception
                ) st.events
            ]
          ]
        , HU.divClass ["block"]
          [ HU.divClass ["card"]
            [ HU.divClass ["card-header"]
              [ HH.p [HU.classes ["card-header-title"]]
                [ HH.text "🔬 Eval" ]
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
                    [ let enabled = st.eval_code /= "" && not st.evaling && st.errorMessage == AllGood in
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

apiPOST :: forall m a b. MonadAff m => EncodeJson a => DecodeJson b =>
  String -> a ->
  H.HalogenM State Action ChildSlots Output m (Maybe b)
apiPOST url content = do
  st <- H.get
  response_or_error <- H.liftAff $ AX.request $ AX.defaultRequest
    { method = Left POST
    , responseFormat = AXRF.string
    , url = url
    , content = Just (AXRB.Json (encodeJson content))
    , headers = [ AXRH.RequestHeader "Authorization" ("Bearer " <> st.loginData.token) ]
    }
  case response_or_error of
    Left err -> do
      Console.log (AX.printError err)
      pure Nothing
    Right response -> do
      if response.status == StatusCode 200
      then case jsonParser response.body of
        Left err -> do
          Console.log ("Body not JSON: " <> err)
          pure Nothing
        Right json -> case decodeJson json of
          Left err -> do
            Console.log "Foo"
            Console.log (printJsonDecodeError err)
            pure Nothing
          Right x -> pure (Just x)
        else
          if response.status == StatusCode 401
          then do
            Console.log "Status code 401, logging out" -- (show response)
            H.raise Logout
            pure Nothing
          else do
            Console.log "status code not 200" -- (show response)
            pure Nothing

reallyUpdateTestStatus :: forall m. MonadAff m => H.HalogenM State Action ChildSlots Output m Unit
reallyUpdateTestStatus = do
  st <- H.get
  H.modify_ (_{errorMessage = Checking })
  r <- apiPOST "/api/test_code" { new_code : st.editorCode }
  for_ r $ \({error}::{error :: Maybe String}) -> do
      H.modify_ (_{errorMessage = maybe AllGood Error error})

updateTestStatus :: forall m. MonadAff m => H.HalogenM State Action ChildSlots Output m Unit
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
    mbr <- apiPOST "/api/get_code" {}
    for_ mbr $ \(r::{botname :: String, code :: String}) -> do
      void $ H.query _ace unit $ H.tell (AceComponent.InitText r.code)
      H.modify_ (_
        { botname = r.botname
        , testCode = r.code
        , editorCode = r.code
        , deployedCode = r.code
        })
    handleAction ReloadMemory
    _ <- H.subscribe timer
    pure unit

  ReloadMemory -> do
    st <- H.get
    mbr <- apiPOST "/api/get_state" {}
    for_ mbr $ \(r::{state :: String, events :: Array LogEvent}) -> do
      H.modify_ (_ { memory = r.state, events = r.events })

  DoLogout -> do
    H.raise Logout

  Deploy -> do
    st <- H.get
    unless (st.loadingTest) $ do
      H.modify_ (_{ deployedCode = st.editorCode })
      _ :: Maybe {} <- apiPOST "/api/set_code" { new_code: st.editorCode }
      pure unit

  Revert ->  do
    st <- H.get
    void $ H.query _ace unit $ H.tell (AceComponent.SetText st.deployedCode)

  ChangeEvalCode s -> H.modify_ (_ { eval_code = s})

  DoEval event -> do
    H.liftEffect $ Event.preventDefault event
    st <- H.get
    unless st.evaling $ do
      H.modify_ (_{evaling = true, eval_message = Nothing })
      mbr <- apiPOST "/api/eval_code" { mod_code: st.editorCode, eval_code: st.eval_code }
      H.modify_ (_{evaling = false})
      for_ mbr $ \({output}::{output :: String}) -> do
        H.modify_ (_ { eval_message = Just output })
        handleAction ReloadMemory

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
