# SimpleRouter

A thin layer over native UIKit navigation. It does not replace
`UINavigationController` — it gives you a central, inspectable, programmatically
drivable store per stack, one place to attach sheets/covers/alerts/dialogs, and a
single handle (`Navigator`) so a screen does not juggle several router objects.

No DSL, no route graph, no generics at the call site. No SwiftUI.

## Why

`UINavigationController` is great, but driving it from code means owning the
view-controller array by hand, and there is no built-in way to ask "what's on this
stack?" or to push from a deep screen without plumbing. SimpleRouter adds exactly
that and nothing more:

- **`NavStack`** — a typed, inspectable stack store (`top`, `depth`, `contains`,
  `pop(to:)`) that owns its `UINavigationController`. It logs every mutation and
  traps misuse (popping past root, popping to a missing route), and adopts
  user-driven pops through the navigation delegate.
- **`Navigator`** — one handle per screen: push onto *this* screen's stack, and
  present / switch root through the app router. Screens adopt
  `NavigatorProviding` and the stack injects the handle.
- **`AppRouter`** — non-generic; owns the current app root and the native
  presentation state (sheet / cover / alert / dialog). Nothing else.

Stacks are owned by the screens that show them (a tab shell owns its tab stacks),
not by the router. Routes render themselves, so there is no central `switch`.

## Install

```swift
.package(url: "https://github.com/maazsurti/SimpleRouter.git", from: "1.0.0")
```

Requires iOS 17+. Logging goes through the `Log` protocol from the `Diagnostics` product of
[Networking](https://github.com/maazsurti/Networking), which SwiftPM fetches with it.

## Quickstart

**1. Define routes that render themselves.**

```swift
import UIKit
import SimpleRouter

struct ProductRoute: RenderableRoute {
    let id: String

    @MainActor func makeViewController() -> UIViewController {
        ProductViewController(id: id)
    }
}
```

A route that needs injected dependencies stays a plain `Hashable` value; the
stack's `makeViewController` closure builds its screen:

```swift
enum AuthRoute: Hashable { case login, signup, forgotPassword }
```

**2. Make a router and show a root.**

```swift
enum AppRoot: Hashable { case auth, main }

let router = AppRouter(root: AppRoot.auth, initialTransition: .fade, logger: consoleLog)

// Routes the router presents itself (sheets/covers) are built here:
router.makeViewController = { route in
    Screens.viewController(for: route, router: router)
}
```

**3. Host the root and swap it on change.**

```swift
final class RootHostViewController: UIViewController {
    private let router: AppRouter
    private var current: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        router.presentingViewControllerProvider = { [weak self] in self }
        router.onRootChange = { [weak self] change in self?.show(change) }
        show(router.root(as: AppRoot.self) ?? .auth, animated: false, transition: router.rootTransition)
    }

    private func show(change: RootChange) {
        show(
            change.root(as: AppRoot.self) ?? .auth,
            animated: change.animated,
            transition: change.transition
        )
    }

    private func show(_ root: AppRoot, animated: Bool, transition: RootTransition) {
        let incoming = Screens.rootViewController(for: root, router: router)
        let outgoing = current
        current = incoming
        addChild(incoming)

        guard animated, let outgoingView = outgoing?.view else {
            incoming.view.frame = view.bounds
            incoming.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(incoming.view)
            outgoing?.willMove(toParent: nil)
            outgoing?.view.removeFromSuperview()
            outgoing?.removeFromParent()
            incoming.didMove(toParent: self)
            return
        }

        transition.animator.animate(from: outgoingView, to: incoming.view, in: view) { [weak outgoing] in
            outgoing?.willMove(toParent: nil)
            outgoing?.removeFromParent()
            incoming.didMove(toParent: self)
        }
    }
}
```

**4. Own a stack, install its root, pass the router.**

`setRootViewController(_:)` installs the stack's root and injects the stack's
`Navigator` into it, so everything in the stack navigates through one handle.

```swift
let stack = NavStack<AnyRoute>(
    "main.home",
    router: router,
    makeViewController: { route in Screens.viewController(for: route, router: router) }
)
stack.setRootViewController(HomeViewController())

// Show `stack.navigationController` wherever the stack belongs: the root host's
// child, one tab's controller, or a pushed screen of another stack.
```

> The stack's root screen is created without the navigator; `setRootViewController`
> injects it (and the router is passed by the screen's factory), so the root can
> navigate from `viewDidLoad` on.

**5. Navigate from any screen in the stack.**

```swift
final class HomeViewController: UIViewController, NavigatorProviding {
    var navigator: Navigator?

    func openProduct() { navigator?.routeTo(ProductRoute(id: "123")) }          // push
    func showHelp()    { navigator?.routeTo(HelpRoute(), presentation: .sheet(.bottom)) }
    func logOut()      { navigator?.showRoot(AppRoot.auth) }
}
```

That's the whole loop: define routes, make a router, own a stack, navigate through
`Navigator`.

## Core types

| Type | Role |
|------|------|
| `RenderableRoute` | A route that builds its own view controller. |
| `AppRouter` | Non-generic. Current root + presentation state. |
| `Navigator` | Per-screen handle: push (this stack) + present / root (router). |
| `NavigatorProviding` | Adopt on a screen to receive its stack's `Navigator`. |
| `NavStack<Route>` | Typed push store that owns one `UINavigationController`. |
| `AnyRoute` | Box so one `NavStack<AnyRoute>` holds mixed route values. |
| `RootChange` / `RootTransition` | Root swap payload and its UIKit animators. |
| `Presentation` / `SheetOptions` | Segue style for `routeTo`: `.push` / `.sheet(_)` / `.cover`. |

Deleted with the SwiftUI implementation: `Host`, `Stack`, `RouterPresentations`,
`ConfirmationDialogModifier`, `OverlayAdapter`, and the `onURL` helper. URL
bridging and overlays belong to the app (see "Out of scope").

## `Navigator` — the screen handle

```swift
nav.routeTo(ProductRoute(id: "1"))                       // push onto this stack
nav.routeTo(HelpRoute(), presentation: .sheet(.bottom))  // present a sheet
nav.routeTo(WelcomeRoute(), presentation: .cover)        // full-screen cover
nav.push(OrderRoute(id: "9"))                            // same as routeTo(_:)
nav.pop()
nav.pop(2)
nav.popToRoot()
nav.showRoot(AppRoot.main)                                // swap the app root
nav.showAlert(title: "Saved")
nav.showConfirmationDialog(title: "Delete?", actions: [AppDialogAction(title: "Delete", role: .destructive) {}])
nav.dismissSheet()
nav.dismissCover()
nav.dismissAllPresentations()
```

`routeTo(_:presentation:)` defaults to `.push` and accepts any `Hashable` route.
Pushes go to the screen's stack; sheets/covers/alerts go to the router.

A screen gets its navigator by adopting `NavigatorProviding`; the stack sets it on
its root and on every pushed screen *before* the screen appears:

```swift
final class DetailViewController: UIViewController, NavigatorProviding {
    var navigator: Navigator?
}
```

Presented screens are not part of a stack, so they get no navigator: they navigate
through the `AppRouter` they were created with (typically injected by the screen
factory).

## `AppRouter` — root + presentations

Non-generic. The root is type-erased; read it back typed with `root(as:)`.

```swift
let router = AppRouter(root: AppRoot.auth, initialTransition: .top, logger: consoleLog)

router.showRoot(AppRoot.main)                  // typed call; stored as AnyHashable
router.showRoot(AppRoot.main, animated: false, transition: .fade)
router.root(as: AppRoot.self)                  // -> AppRoot?
router.rootGeneration                          // bumps on every showRoot, even unchanged
```

State it exposes: `root`, `rootTransition`, `rootGeneration`, `sheet`,
`fullScreenCover`, `alert`, `confirmationDialog` (all `private(set)`; drive them
through the methods). Root-level screens that are not inside a stack (a splash, an
onboarding screen) use `AppRouter` directly; everything inside a stack uses
`Navigator`.

Three hooks wire the router to the app, all set on the root host:

| Hook | Purpose |
|------|---------|
| `onRootChange: ((RootChange) -> Void)?` | Rebuild the visible root on every change. |
| `presentingViewControllerProvider: (() -> UIViewController?)?` | Where modals are presented from; the router walks to the top-most controller. |
| `makeViewController: ((AnyRoute) -> UIViewController)?` | Builds the screen for routes the router presents that do not render themselves. |

A missing `presentingViewControllerProvider` (or one that returns `nil`) is an app
wiring bug: the router logs it and calls `assertionFailure`. The same goes for
presenting a route that neither renders itself nor has a resolver.

## Root switching

`showRoot(_:animated:transition:)` bumps `rootGeneration` **even when the root value
is unchanged**, so a re-showed root re-establishes the content owned by it (an auth
deep-link path, for example) instead of silently no-opping. The host rebuilds its
child from the published `RootChange`.

`RootTransition` keeps `.fade` and `.top` and hands the host an animator:

```swift
public protocol RootTransitionAnimator {
    @MainActor func animate(from outgoing: UIView?, to incoming: UIView, in container: UIView, completion: @escaping () -> Void)
}
RootTransition.fade.animator   // FadeRootTransitionAnimator — cross-dissolve
RootTransition.top.animator    // TopRootTransitionAnimator — slide through the top edge
```

The animator owns the visual swap: it adds the incoming view, animates it, removes
the outgoing view, then calls `completion`. The host owns view-controller
containment around that call.

## Stacks and routes

Every stack is a `NavStack<AnyRoute>`; a route either renders itself
(`RenderableRoute`) or is built by the app's factory. Even a linear flow (auth) is
just an enum:

```swift
enum AuthRoute: RenderableRoute {
    case signup, forgotPassword

    @MainActor func makeViewController() -> UIViewController {
        switch self {
        case .signup:         SignupViewController()
        case .forgotPassword: ForgotPasswordViewController()
        }
    }
}

nav.routeTo(AuthRoute.signup)
```

`NavStack` is inspectable and bounded: `push`, `pop`, `pop(_:)`, `pop(to:)`,
`popToRoot`, `replace`, plus `top` / `depth` / `isEmpty` / `contains`. Misuse is
logged and trapped (debug) rather than corrupting navigation silently, and a
user-driven pop (interactive swipe-back) is adopted into `routes` through the
navigation delegate.

The navigation controller a stack owns hides the system navigation bar once for the
whole stack — screens draw their own chrome — and re-enables the interactive pop
gesture with a `nil` delegate, so swipe-back keeps working behind a custom back
button. A screen that wants the system bar back can call
`setNavigationBarHidden(false)`.

`NavStack<Route>` is generic so a stack can hold typed routes (`NavStack<Int>`,
`NavStack<AuthRoute>`); `NavStack<AnyRoute>` additionally owns a `Navigator` and
gains the ergonomic overloads that box any `Hashable` route for you.

Installing the root:

```swift
stack.setRootViewController(homeViewController)   // injects the navigator, keeps routes above it
```

> **Retain the stack.** `UINavigationController.delegate` is weak, so keep the
> `NavStack` (or one of its screens' `Navigator`) alive for as long as the
> navigation controller is on screen. An app that installs its own navigation
> delegate must forward `navigationController(_:didShow:animated:)` to the stack or
> user-driven pops stop syncing.

## Presentations

Drive the four native surfaces through `Navigator` (or `AppRouter`):

```swift
nav.routeTo(HelpRoute(), presentation: .sheet(.bottom))
nav.routeTo(HelpRoute(), presentation: .sheet(SheetOptions(detents: [.medium, .large])))
nav.routeTo(WelcomeRoute(), presentation: .cover)
nav.showAlert(title: "Saved", message: "Your changes were saved.")
nav.showConfirmationDialog(
    title: "Delete item?",
    actions: [AppDialogAction(title: "Delete", role: .destructive) { delete() }]
)
nav.dismissAllPresentations()
```

`SheetOptions` maps onto `UISheetPresentationController`:

| Option | UIKit |
|--------|-------|
| `detents: Set<SheetDetent>` (`.medium`, `.large`) | `sheetPresentationController.detents`, ascending so the smallest is the opening size |
| `dragIndicator` (`.automatic`, `.visible`, `.hidden`) | `prefersGrabberVisible`; `.automatic` shows it for a resizable (multi-detent) sheet |
| `cornerRadius` | `preferredCornerRadius` when set |
| `interactiveDismissDisabled` | `isModalInPresentation` |

`.bottom` is a ready-made medium/large bottom sheet.

Alerts are `UIAlertController`s: `showAlert` presents `.alert` with a single OK
button (which clears the state), and `showConfirmationDialog` presents an
`.actionSheet` with one action per `AppDialogAction` (`role` →
`.destructive` / `.cancel` / `.default`, and an iPad popover anchor). UIKit action
sheets always have room for a title, so `DialogTitleVisibility.hidden` presents the
dialog without one — the only place this port loses SwiftUI detail.

Presentations are **single slot**: presenting a sheet or cover while one is on
screen dismisses the old one first, and alerts layer over whatever modal is up.
A modal the user dismisses (swipe down, tap outside) clears the router state
through the presentation-controller delegate.

Dismiss through the router: `dismissSheet()`, `dismissCover()`,
`dismissAllPresentations()`, `dismissConfirmationDialog()`.

## Logging

The router logs through the `Log` protocol from the **LogKit** module — inject a
`Log` and you see every push, pop, root switch, and presentation:

```swift
let router = AppRouter(root: AppRoot.auth,
                       logger: ConsoleLog(label: "MyApp", isEnabled: { isDebug }))
```

`Log` is a one-method protocol (`write(_:level:category:)`); `ConsoleLog` is the
default print-based sink. Pass `nil` to disable logging. Messages are tagged with
`RouterLogCategory` (`ROUTER`, `URL`, `PRESENTATION`), so an app's logger can filter
by it — `URL` is reserved for app-side URL handling.

## Out of scope

Things the SwiftUI version provided that are now the app's business, because UIKit
already has first-class answers:

- **URL handling** — parse URLs in app code and call the router; queue them in a
  small `URLBridge` and drain it from `scene(_:openURLContexts:)` /
  `sceneDidBecomeActive`.
- **Overlays** (toasts, loading) — present them from a `UIWindow` or a child view
  controller of your root host.
- **Tab shells** — one `UINavigationController` per tab, each with its own
  `NavStack`; swap the visible tab's controller yourself.
