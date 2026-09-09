# Backend bug: `isFollowing` is always `false` on `GET /creators/{id}` and `GET /brands/{id}`

**Reported:** 2026-08-27
**Severity:** High — follow state never persists across screen reloads in the client
**Affected endpoints:**
- `GET /api/v1/creators/{id}`
- `GET /api/v1/brands/{id}`

## Symptom (client-visible)

Follow a creator (or brand) from their public profile screen, navigate back,
reopen the profile. The button shows **Follow** again instead of **Following**,
even though the follow was persisted (follower count increments, and the user
appears in the creator's followers list).

## Root cause

Both profile endpoints return an `isFollowing` field, documented as
_"Whether the authenticated user is following this creator"_
(`CreatorSummary` schema, `openapi.yaml`). In practice the field is **always
`false`**, regardless of the caller's bearer token and regardless of whether
the follow relationship exists.

The follow itself works — `POST /creators/{id}/follow` persists the edge and
`GET /creators/{id}/followers` reflects it immediately. Only the
`isFollowing` flag on the profile response is wrong.

## Live reproduction (2026-08-27)

Creator `6a6776a289d52fb6fb9ee199` ("Tushar"), authenticated as a freshly
registered player (`6a50f37d5cadf271870a200c`):

```
$ curl -s -X POST .../api/v1/creators/6a6776a289d52fb6fb9ee199/follow \
       -H "Authorization: Bearer <token>"
{"status":"success","data":{"following":true,"followingType":"creator"}}

$ curl -s .../api/v1/creators/6a6776a289d52fb6fb9ee199/followers?limit=10 \
       -H "Authorization: Bearer <token>"
# → response list includes { followerId: { _id: "6a50f37d5cadf271870a200c", ... } }

$ curl -s .../api/v1/creators/6a6776a289d52fb6fb9ee199 \
       -H "Authorization: Bearer <token>"
{"status":"success","data":{
   "creator": { "_id": "6a6776a289d52fb6fb9ee199", ... },
   "isFollowing": false          ← WRONG, the caller follows this creator
}}
```

Identical behavior confirmed for `GET /brands/{id}` with
`POST /brands/{id}/follow`.

## Expected

`data.isFollowing` should be `true` when a follow edge exists between the
authenticated caller and the target creator/brand (`followerId = caller`,
`followingId = {id}`, matching `followingType`), and `false` otherwise. For
unauthenticated / no-token requests, `false` is fine.

## Notes for the fix

- The response shape nests the profile under `data.creator` / `data.brand`
  with `isFollowing` as a **sibling** key — that nesting is fine, just the
  value that's wrong.
- `openapi.yaml` does not mark `GET /creators/{id}` or `GET /brands/{id}`
  with `security: BearerAuth`. If the route currently has no auth middleware
  attached, that would explain why it can't resolve the caller — the flag
  needs the authenticated user id to be resolvable (optional auth is enough;
  it should still return `false` for anonymous callers).
- A dedicated "am I following {id}" endpoint would also resolve this
  client-side, but fixing the existing flag is the smaller change and needs
  no client rework beyond what's already shipped.

## Client-side status

The client had a second, independent bug: `CreatorsService.fetchCreator` /
`BrandsService.fetchBrand` unwrapped the response to `data.creator` /
`data.brand` and discarded the sibling `isFollowing`. Fixed on
`prototype` (the flag is now lifted into the returned map), so once the
backend returns a correct value the profile screens will reflect it with no
further client changes.
