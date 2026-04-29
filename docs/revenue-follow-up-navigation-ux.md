# Revenue Follow-Up Navigation UX

## Final visible branch rail
- Dashboard
- Workbench
- Quotes
- Back Orders
- Ready to Ship
- Freight Recovery
- Analytics


## Removed visible labels
- Follow-Up Queue
- Overdue Quotes
- Team Progress

## Renamed visible labels
- Backorder Lines -> Back Orders
- Freight Ledger -> Freight Recovery

## Route compatibility
Internal routes remain compatible where needed:
- Workbench uses the existing team-progress route internally, but the visible label/title is Workbench.
- Back Orders uses the existing overdue-backorders route internally, but the page now presents Back Orders as the all-backorder review surface.
- Freight Recovery uses the existing freight-worklist route internally, but the visible label/title is Freight Recovery.
