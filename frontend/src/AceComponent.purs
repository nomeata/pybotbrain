module AceComponent where

import Prelude

import Ace as Ace
import Ace.EditSession as Session
import Ace.Editor as Editor
import Ace.UndoManager as UndoManager
import Ace.Types (Editor)
import Data.Foldable (traverse_, for_)
import Data.Maybe (Maybe(..))
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.Query.EventSource as ES

type Slot = H.Slot Query Output

data Query a
  = InitText String a
  | SetText String a

data Output = TextChanged String

data Action
  = Initialize
  | Finalize
  | HandleChange

-- | The state for the ace component - we only need a reference to the editor,
-- | as Ace editor has its own internal state that we can query instead of
-- | replicating it within Halogen.
type State = { editor :: Maybe Editor }

-- | The Ace component definition.
component :: forall i m. MonadAff m => H.Component HH.HTML Query i Output m
component =
  H.mkComponent
    { initialState
    , render
    , eval: H.mkEval $ H.defaultEval
        { handleAction = handleAction
        , handleQuery = handleQuery
        , initialize = Just Initialize
        , finalize = Just Finalize
        }
    }

initialState :: forall i. i -> State
initialState _ = { editor: Nothing }

-- As we're embedding a 3rd party component we only need to create a placeholder
-- div here and attach the ref property which will let us reference the element
-- in eval.
render :: forall m. State -> H.ComponentHTML Action () m
render = const $ HH.div [ HP.ref (H.RefLabel "ace") ] []

handleAction :: forall m. MonadAff m => Action -> H.HalogenM State Action () Output m Unit
handleAction = case _ of
  Initialize -> do
    H.getHTMLElementRef (H.RefLabel "ace") >>= traverse_ \element -> do
      editor <- H.liftEffect $ Ace.editNode element Ace.ace
      H.liftEffect $ Editor.setMinLines 25 editor
      H.liftEffect $ Editor.setMaxLines 1000 editor
      H.liftEffect $ Editor.setAutoScrollEditorIntoView true editor
      H.liftEffect $ Editor.setTheme "ace/theme/terminal" editor
      H.liftEffect $ Editor.setFontSize "120%" editor
      session <- H.liftEffect $ Editor.getSession editor
      H.liftEffect $ Session.setMode "ace/mode/python" session
      H.modify_ (_ { editor = Just editor })
      void $ H.subscribe $ ES.effectEventSource \emitter -> do
        Session.onChange session (\_ -> ES.emit emitter HandleChange)
        pure mempty
  Finalize -> do
    -- Release the reference to the editor and do any other cleanup that a
    -- real world component might need.
    H.modify_ (_ { editor = Nothing })
  HandleChange -> do
    H.gets _.editor >>= traverse_ \editor -> do
      text <- H.liftEffect (Editor.getValue editor)
      H.raise $ TextChanged text

handleQuery :: forall m a. MonadAff m => Query a -> H.HalogenM State Action () Output m (Maybe a)
handleQuery = case _ of
  InitText text next -> do
    maybeEditor <- H.gets _.editor
    for_ maybeEditor $ \editor -> H.liftEffect $ do
      void $ Editor.setValue text (Just 1) editor
      Editor.getSession editor >>= Session.getUndoManager >>= UndoManager.reset

    H.raise $ TextChanged text
    pure (Just next)

  SetText text next -> do
    maybeEditor <- H.gets _.editor
    for_ maybeEditor $ \editor -> H.liftEffect $ do
      void $ Editor.setValue text (Just 1) editor

    H.raise $ TextChanged text
    pure (Just next)
