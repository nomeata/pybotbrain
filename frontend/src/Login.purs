module Login where

import Prelude

import Data.String as String
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Foldable (foldMap, for_)
import Effect.Aff.Class (class MonadAff)
import Affjax as AX
import Affjax.StatusCode (StatusCode(..))
import Affjax.ResponseFormat as AXRF
import Affjax.RequestBody as AXRB
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.HTML.Events as HE
import Web.Event.Event (Event)
import Web.Event.Event as Event
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage as Storage
import Data.Argonaut (encodeJson, decodeJson, printJsonDecodeError)

import HTMLUtils as HU
-- import Debug.Trace as Debug

type Slot = H.Slot (Const Void) LoginData

type LoginData =
   { token :: String
   }

type State =
   { password :: String
   , loading :: Boolean
   , lastError :: Maybe String
   }

data LoginAction
  = Initialize
  | ChangePassword String
  | DoLogin Event

component :: forall f i m. MonadAff m => H.Component HH.HTML f i LoginData m
component =
  H.mkComponent
    { initialState: \_ -> {
        password: "",
        lastError: Nothing,
        loading: false
      }
    , render: renderLogin
    , eval: H.mkEval $ H.defaultEval {
        handleAction = handleLoginAction,
        initialize = Just Initialize
      }
    }

renderLogin :: forall m. MonadAff m => State -> H.ComponentHTML LoginAction () m
renderLogin st = HU.fullHeight $
  HU.divClass ["container", "has-text-centered"]
    [ HU.divClass ["column","is-4","is-offset-4"]
      [ HH.h1  [ HU.classes ["title"] ] [ HH.text "Bot Control Center" ]
      , HH.hr_
      , HH.p  [ HU.classes ["subtitle"] ]
        [ HH.text "Send /login to your bot to get a password!" ]
      , HH.form
        [ HE.onSubmit \e -> Just (DoLogin e)
        ] $
        [ HU.divClass ["field"]
          [ HU.divClass ["control"]
            [ HH.input
              [ HU.classes ["input", "is-large", "has-text-centered"]
              -- , HP.type_ HP.InputPassword
              , HP.name "password"
              , HP.value st.password
              , HE.onValueInput (Just <<< ChangePassword)
              , HP.placeholder "ABCDEF"
              ]
            ]
          ]
        , HU.divClass ["field"]
          [ HU.divClass (["control"] <> (if st.loading then ["is-loading"] else []))
            [ HH.button
              [ HP.disabled (not can_login)
              , HU.classes ["button", "is-link", "is-large", "is-fullwidth"]
              ]
              [ HH.text "Login" ]
            ]
          ]
        ] <> (foldMap (\err -> [ HH.p_ [ HH.text err] ]) st.lastError )
      ]
    ]
  where
    can_login = not st.loading && String.length st.password == 6

handleLoginAction :: forall m.  MonadAff m => LoginAction -> H.HalogenM State LoginAction () LoginData m Unit
handleLoginAction = case _ of

  Initialize -> do
    pw <- H.liftEffect $ do
      w <- window
      s <- localStorage w
      Storage.getItem "token" s
    for_ pw $ \token -> H.raise {token}

  ChangePassword s -> H.modify_ (_ { password = String.toUpper s})

  DoLogin event -> do
    H.liftEffect $ Event.preventDefault event
    {password} <- H.get

    H.modify_ (_ { loading = true })
    response_or_error <- H.liftAff $ AX.post AXRF.json "/api/login" (Just (AXRB.Json (encodeJson {password})))
    H.modify_ (_ { loading = false} )
    case response_or_error of
      Left err -> H.modify_ (_ {lastError = Just (AX.printError err) })
      Right response -> do
        if response.status == StatusCode 200
        then case decodeJson response.body of
          Left err -> H.modify_ (_ {lastError = Just (printJsonDecodeError err) })
          Right ({token}::{token :: String}) -> do
            H.liftEffect $ do
              w <- window
              s <- localStorage w
              Storage.setItem "token" token s
            H.raise {token}
        else case decodeJson response.body of
          Left err -> H.modify_ (_ {lastError = Just (printJsonDecodeError err) })
          Right ({error}::{error :: String}) -> H.modify_ (_ {lastError = Just error })
