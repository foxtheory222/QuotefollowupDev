# Browser Tests Not Run

Browser automation was not run in this pass.

Reason:

- the implementation scope was source hardening and static verification only
- no live deployment was performed in this pass, so browser verification against the current production site would not validate the unshipped source changes

Manual checklist for follow-up review after a separate deploy decision:

1. Open `/`
2. Open `/southern-alberta`
3. Open `/southern-alberta/4171-calgary`
4. Open `/southern-alberta/4172-lethbridge`
5. Open `/southern-alberta/4173-medicine-hat`
6. Open one detail route that displays `qfu_deliverynotpgi`
7. Open `/ops---admin` if the route is enabled
8. Confirm no uncaught console errors
9. Confirm degraded-data diagnostics render if a critical dataset fails
10. Confirm delivery-not-PGI stale warning uses base-row freshness and not comment-update freshness
