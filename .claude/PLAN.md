---
task: Two-scope transfer parity — spendable + with-confirmation plan, and the Android enter-amount / privacy-confirmation UI
date: 2026-09-05
status: draft
source: ../polkadot-android-community (RealPrepareCoinageTransferUseCase, SendEnterAmount*, SendValidation, SendConfirmGainingPrivacyBottomSheet) + ../Coinage/privacy/transfer-spendable.png, transfer-confirmation.png
files_touched:
  # Backend — Coinage package (the parity gap)
  - Packages/Coinage/Sources/CoinageService.swift: previewTransfer tries .spendable then falls back to .withConfirmation; carries the scope
  - Packages/Coinage/Sources/Transfer/TransferPreview.swift: add `scope: SpendScope`
  # App — TransferAmount enter-amount screen (match Android)
  - polkadot-app/Modules/TransferAmount/Model/TransferSpendableBreakdown.swift: rename fields secured/lowPrivacy → availablePrivate/gainingPrivacy
  - polkadot-app/Modules/TransferAmount/TransferAmountInteractor.swift: feed availablePrivate/gainingPrivacy(+confirmable); surface preview scope
  - polkadot-app/Modules/TransferAmount/TransferAmountPresenter.swift: Max = availablePrivate; extra hint = gainingPrivacy; input cap = available; confirmation gating on scope
  - polkadot-app/Modules/TransferAmount/TransferAmountProtocols.swift: peer — presenter/interactor/wireframe method additions
  - polkadot-app/Modules/TransferAmount/BalanceInfo/BalanceInfoModel.swift: reshape to max + extra-hint (drop secured/lowPrivacy sub-rows)
  - polkadot-app/Modules/TransferAmount/BalanceInfo/BalanceInfoViewLayout.swift: render `Max:` + `Extra … privacy` per screenshots
  - polkadot-app/Modules/TransferAmount/TransferAmountViewLayout.swift: `Max:` line + optional extra-privacy hint above the amount
  - polkadot-app/Modules/TransferAmount/TransferAmountWireframe.swift: showGainingPrivacyConfirmation(...)
  # App — confirmation sheet (repurpose the now-dead TransferPrivacy module)
  - polkadot-app/Modules/TransferPrivacy/ActionSheet/TransferPrivacyModel.swift: single "Send X anyway" gaining-privacy model
  - polkadot-app/Modules/TransferPrivacy/ActionSheet/TransferPrivacyPresenter.swift: title/body/anyway/cancel
  - polkadot-app/Modules/TransferPrivacy/ActionSheet/TransferPrivacyViewLayout.swift: info icon + title + body + Send-anyway + Cancel
  - polkadot-app/Modules/TransferPrivacy/ActionSheet/TransferPrivacyProtocols.swift: peer
  - polkadot-app/Modules/TransferPrivacy/CoinagePrivacyPresenting.swift: onSendAnyway/onCancel contract
  # Strings + docs
  - polkadot-app/Localization/Localizable.xcstrings: 5 new keys (hand-edit; extractionState manual)
  - .claude/docs/architecture/coinage.md: document the two-scope plan + confirmation flow
  # Tests
  - polkadot-appTests/Coinage/CoinageAssetSelectorTests.swift: NEW — scope widening (runnable)
seams_used:
  - SpendScope + CoinageAssetSelector (already present; widens only when allowsConfirmedSpend)
  - CoinageService.selectableAssets(scope:) (already scope-aware; only the orchestration is missing)
  - CoinSelectionError.insufficientFunds/.emptyWallet as the spendable→withConfirmation fallback trigger
  - TransferPreview as the carrier of the chosen scope to the presenter
must_not_touch:
  - CoinageAssetSelector / SpendScope logic (matches Android exactly already)
  - The recycling evaluator, balance service, on-chain submission
out_of_scope:
  - Fiat conversion of the hint/confirmation amounts beyond the existing amount formatter
  - Any change to how availablePrivate/gainingPrivacy are computed (balance is done)
open_questions: []
---

## Goal

Reach Android parity for outgoing coinage transfers: build the transfer plan against **both** spend
scopes (spendable first, then with-confirmation) instead of spendable only, and present the Android
enter-amount screen — `Max: {availablePrivate}` with an `Extra {gainingPrivacy} is spendable, but at the
risk of reducing your privacy` hint — gating any spend that dips into gaining-privacy funds behind the
"This payment might reduce your privacy" confirmation sheet.

## Approach

### 1. Backend — plan for both scopes (the actual parity gap)

iOS already has `SpendScope { spendable, withConfirmation }` and a `CoinageAssetSelector` that widens to
`toRecycle` coins + `gainingPrivacy` vouchers only when `allowsConfirmedSpend` — matching Android's
`getSelectable*ByScope` exactly. The only missing piece is the orchestration in
`CoinageService.previewTransfer`, which today selects `scope: .spendable` and stops.

Mirror Android's `RealPrepareCoinageTransferUseCase.preparePlan`
(`planWithin(SPENDABLE).flatRecover { planWithin(WITH_CONFIRMATION) }`):

```swift
public func previewTransfer(for amount: BigUInt) async throws -> TransferPreview {
    guard let context = breakdownContext else { throw CoinageError.notConfigured }
    let coins = try await coinService.fetchAllTrackedCoins()
    let vouchers = try await voucherService.fetchAllTracked()

    // Spendable first; widen to gaining-privacy funds only if spendable cannot cover the amount.
    for scope in [SpendScope.spendable, .withConfirmation] {
        let (c, v) = await selectableAssets(coins: coins, vouchers: vouchers, scope: scope)
        do {
            let result = try await senderService.previewStrategy(
                amount: amount, availableCoins: c, availableVouchers: v, breakdownContext: context
            )
            return TransferPreview(selectionResult: result, fullAmount: amount, scope: scope)
        } catch CoinSelectionError.insufficientFunds, CoinSelectionError.emptyWallet {
            continue   // try the wider scope
        }
    }
    throw CoinSelectionError.insufficientFunds
}
```

`.withConfirmation` collapses to `.spendable` under `maxPrivacy` (the selector never widens when
`allowsConfirmedSpend == false`), so the second pass is a no-op there and the loop still terminates in
`insufficientFunds`. `TransferPreview` gains `let scope: SpendScope` so the presenter knows whether the
resulting plan spends gaining-privacy funds.

### 2. UI — enter-amount screen (match the screenshots)

`TransferSpendableBreakdown` becomes `{ availablePrivate, gainingPrivacy }` (canSpendWithConfirmation
already folded in interactor-side: `gainingPrivacy = canSpendWithConfirmation ? amount : 0`). The
presenter maps, per Android `SendEnterAmountViewModel`:

- **`Max: {availablePrivate}`** — headline cap label (was `secured + lowPrivacy`).
- **`Extra {gainingPrivacy} is spendable, but at the risk of reducing your privacy`** — shown only when
  `gainingPrivacy > 0` (i.e. offerable).
- **input validation cap = `availablePrivate + gainingPrivacy` (= balance.available / reachable)** — so
  the field accepts amounts into the gaining-privacy range; `calculateMax()` returns this.

`BalanceInfoModel`/`BalanceInfoViewLayout` drop the `secured`/`lowPrivacy` sub-rows and render the two
Android lines; `TransferAmountViewLayout` shows `Max:` + the optional hint above the amount.

### 3. Confirmation flow (repurpose the dead TransferPrivacy module)

Android `SendValidation` decides on submit:
- `amount ≤ availablePrivate` → send directly (plan is `.spendable`).
- `availablePrivate < amount ≤ available` (and confirmable) → show the sheet; on "anyway", send.
- `amount > available` or not confirmable → balance error.

On iOS this maps to the **plan scope already resolved by `previewTransfer`**: the presenter shows the
confirmation iff `preview.scope == .withConfirmation`, else submits directly. The now-dead
`TransferPrivacy/ActionSheet` module (previously the degraded-vs-secured sheet) is repurposed into the
single-action gaining-privacy confirmation: info icon, title, body, `Send {amount} anyway`, `Cancel`.
`onSendAnyway` → `executeTransfer(preview.selectionResult)`; `Cancel` → dismiss.

### 4. Strings (hand-edit xcstrings, extractionState manual)

| key | en |
|---|---|
| `transfer.amount.max` | `Max:` |
| `transfer.amount.privacyHint` | `Extra %@ is spendable, but at the risk of reducing your privacy` |
| `transfer.privacy.confirm.title` | `This payment might reduce your privacy` |
| `transfer.privacy.confirm.body` | `In this payment you are using funds that have not yet been fully processed by the privacy system.` |
| `transfer.privacy.confirm.sendAnyway` | `Send %@ anyway` |

Reuse the existing Cancel string.

## Steps

1. **TransferPreview.scope + previewTransfer fallback** (§1). Build + a unit check on the loop.
2. **TransferSpendableBreakdown reshape** + interactor mapping (availablePrivate/gainingPrivacy).
3. **Presenter**: Max/hint/cap mapping; confirmation gating on `preview.scope`.
4. **BalanceInfo + TransferAmountViewLayout**: Android `Max:` + hint layout.
5. **Confirmation sheet**: repurpose TransferPrivacy/ActionSheet; wire wireframe + protocols.
6. **Strings** in xcstrings; reference via generated symbols.
7. **Tests**: `CoinageAssetSelectorTests` (scope widening: spendable = allowUse+usable; withConfirmation
   adds toRecycle+gainingPrivacy only when confirmable; maxPrivacy never widens). Runnable app target.
8. **Docs**: coinage.md two-scope plan + confirmation flow.

## North-Star Alignment

The plan already models privacy as a policy the balance reflects; this closes the transfer side so the
user can *choose* to spend gaining-privacy funds behind an explicit, informed confirmation — never
silently. Scope is stated at the plan boundary (Android's rule: "picking the wrong one silently spends
privacy they were buying"), carried by `TransferPreview`, and surfaced as the confirmation.

## Risks

- **previewTransfer is called per keystroke** — the double pass (spendable then withConfirmation) doubles
  selection work only when the amount exceeds spendable. Mitigation: the fallback runs only on
  `insufficientFunds`; spendable-covered amounts short-circuit on the first pass.
- **Repurposing TransferPrivacy** — the module's old two-amount (degraded/secured) contract is replaced by
  a one-action confirmation; any lingering references to the old `TransferPrivacyModel` fields must be
  updated (compile-driven).
- **`available` cap vs `Max:` label divergence** — the field accepts up to `available` while the label
  shows `availablePrivate`; a test pins that typing into the gaining-privacy range enables send and routes
  through the confirmation, and that `> available` is rejected.

## Verification

- [ ] `previewTransfer` returns `.spendable` when spendable covers the amount, `.withConfirmation` when it
      only reaches with gaining-privacy funds, and throws when neither does (unit).
- [ ] `maxPrivacy`: second pass never widens; over-spendable amounts throw (unit).
- [ ] Enter-amount shows `Max: availablePrivate` and the hint only when gainingPrivacy > 0.
- [ ] Amount in the gaining-privacy range → confirmation sheet → "anyway" submits; Cancel aborts.
- [ ] No references remain to `TransferSpendableBreakdown.secured/.lowPrivacy` or the old TransferPrivacy
      degraded model.
- [ ] Build + targeted tests pass (`test_sim`), coinage.md updated.
