# Current State (handoff)

Handoff note between Claude sessions. Permanent rules live in `CLAUDE.md`.
If this file conflicts with the actual files or git state, trust the files/git and report the discrepancy first.

## SPRINT1+INT-08+INT-09 = LIVE, PRODUCTION VERIFIED (deployed 2026-11-03, Cloudflare deployment 34702cbd-32b8-4fa2-942a-5ba3d1c5a852)

- Sprint 1 (INT-01..05): new `transfers/liberia-airport-to-tamarindo.html`; blog guide LIR updated with 4 CTAs; `destinations/papagayo.html` updated with seo_title/desc override; `hotels.html` meta updated (INT-02); `sitemap.xml` 178→179 URLs; `llms.txt` +Tamarindo.
- INT-08: `tours.html` 7 SEO fields updated (title, meta description, og/twitter, schema CollectionPage name).
- INT-09: Bubu `assistant-knowledge.json` 4→5 transfers (+Tamarindo); `_worker.js` compiled by wrangler 4.157.0 (259.1 KB), `/assistant` and `/health` routes confirmed.
- Package SHA-256: 936723B52B2AFB03EC21BC8FB14A15EC0961FE68D512FC6FFD600AB363D94A39 (71.6 MB, 910 files). 7 files uploaded, 903 already cached by CF.
- Post-deploy: wildpapagayo.com 200 on /transfers/liberia-airport-to-tamarindo; all 5 transfer pages 200; 4 LIR blog CTAs confirmed; Tamarindo in sitemap.xml + llms.txt; /health {"status":"ok"}; Bubu responds correctly about Tamarindo (1h20min, hotels, transfer URL); P026 returns 404.
- Rollback: dashboard > Deployments > cd38c5d2-7a55-471d-8b8d-59d8bd380ecf > Rollback.
- IndexNow NOT submitted — pending separate GO from owner.
- No commits, no push.

## CACHE-REMEDIATION-4FILES = superseded by Sprint 1 deploy above (the 4 replacement files now return 404, as documented as acceptable in the Release Gate). Previously deployed as cd38c5d2-7a55-471d-8b8d-59d8bd380ecf.

- Temporary security mitigation for the stale-cache incident (see PHASE5 below): production now serves harmless replacements at the 4 removed URLs: `blog-data.json` = `{}`, `knowledge-validation-report.txt` / `hotel-knowledge-report.txt` / `tour-knowledge-report.txt` = `This resource is no longer available.` (no trailing newline). The original contents were NOT restored anywhere.
- Package: C:\Users\Admin\wild-papagayo-backups\release-candidate-rem4-20261103T112413Z (+ .sha256, 920 files) = 1861f180 baseline + exactly 4 added files, 0 modified, 0 removed. Deployed with `wrangler pages deploy <package> --project-name=wild-papagayo --branch=main --commit-dirty=true`, exit 0, 4 uploaded / 909 already present. deploy-package.ps1 NOT run, no IndexNow, no purge, nothing committed.
- Verified 11:25–12:10 UTC: wildpapagayo.com, www, http, wild-papagayo.pages.dev and cd38c5d2.wild-papagayo.pages.dev all return 200 with only the replacement bytes, `Cache-Control: public, max-age=0, must-revalidate`, new ETags, no Age/s-maxage; old ETags no longer revalidate (200 with new body). Original content no longer accessible. 913 served files byte-identical to the package; 178 sitemap URLs 200; tours/SEO 554 checks with only the 4 pre-existing failures; targeted 13/13; functional 28 PASS (+1 known faulty test); menu/Bubu 109/109 on transfer page, /transport, a tour and Home; 486-job matrix 0 errors/overflow/broken images, max CLS 0.0602; /health 200, /assistant unchanged.
- Pre-deploy evidence of the stale originals (headers + bodies, CF-Rays a54b02ac…/a54b02af…/a54b02b1…/a54b02b3…) kept in the session scratchpad `rem4/pre`; earlier incident evidence in `p5rel/incident`.
- deploy-package.ps1 still excludes these 4 names, so a future deploy-package.ps1 build will drop the replacements (URLs then return 404, which is also safe now that the stale copies are gone). Repo working tree still holds the original blog-data.json and 3 reports (needed by the generators; never ship them).
- Rollback: dashboard > Deployments > 1861f180-db47-499f-a0ff-761f40358070 > Rollback (the 4 URLs would then 404 at origin; the stale edge copy should not return since it was replaced, but re-check).

## PRODUCTION BASELINE = 1861f180-db47-499f-a0ff-761f40358070 (GEO Fase 9.6 on top of Phase 5), ADOPTED 2026-11-03 by owner authorization

- Origin: deployed 2026-11-03 03:07:49 UTC by Claude session 50e89238 (GEO Fases 9.x) after the owner's "GO DEPLOY FASE 9.6"; package from `deploy-package.ps1 -BuildFunctions` (source commit 9b9cd76 + working tree, 916 files). Same session ran `indexnow-submit.ps1` at 03:31 UTC (178 URLs, 200) under the owner's "CIERRE TÉCNICO" prompt and made local commit 25dc0c2 (not pushed). It did not update this file.
- Difference vs 8eea9883 (Phase 5): new `transfers/liberia-airport-to-papagayo-peninsula.html`; `transport.html` "Popular Transfer Routes" block; `sitemap.xml` 177 -> 178 URLs; `llms.txt` +1 line; assistant knowledge (functions/, netlify/functions/, `_worker.js`) +1 transfer; `_worker.js`/`_routes.json` wrangler 4.156.2 router code/version. Everything else byte-identical (all 33 tours, prices, policies, Phase 5 CSS/JS).
- Read-only investigation 2026-11-03: 909 served files byte-identical to the package; no secrets, no unpublished content (P026 excluded, 404); live regression clean (486-job matrix 0 errors, tours/SEO only the 4 pre-existing failures, menu/Bubu 109/109 x3, 178 sitemap URLs 200). Verdict A, safe to keep. Re-verified 2026-11-03 11:22 UTC (909/909 match).
- Baselines: ../wild-papagayo-deploy-current-baseline = 1861f180 package (+ .BASELINE.txt). Immutable copies (read-only, with .sha256): C:\Users\Admin\wild-papagayo-backups\prod-1861f180-20261103 and, as rollback reference, prod-8eea9883-20261102 (Phase 5).
- Rollback: Cloudflare dashboard > wild-papagayo > Deployments > 8eea9883-4bd0-4ba9-9b6d-a3c593a66a51 > Rollback (removes the GEO 9.6 transfer page).
- Release coordination: two Claude sessions released this project concurrently on 2026-11-02/03. Before any `wrangler pages deploy`, check for `..\WEBSITE-RELEASE.LOCK` (Tico 10 folder) and do not deploy while another session holds it.

## PHASE5-UX-IMAGES-SEO-2026-11-02 = LIVE, PRODUCTION VERIFIED EXCEPT 4 STALE REMOVED URLS (deployed 2026-11-02 ~21:09 UTC, Cloudflare deployment 8eea9883-4bd0-4ba9-9b6d-a3c593a66a51)

Final live verification on https://wildpapagayo.com, 2026-11-02 21:48–22:28 UTC, after the owner's manual Custom Purge of 8 URLs:
- PASS: script.js, style.css, style.min.css, assistant-widget.js byte-identical to the 8eea9883 package (sha256 706a5d53…, 4640dc89…, fb632dac…, 8b66113f…; cf-cache-status MISS right after the purge).
- PASS: mobile menu (opens, pins page, Escape closes + restores scroll and focus), Bubu open/close, landscape panel, tooltip, floating buttons with no overlap: 109/109 on each of a tour, Home, a destination and a hotel page, at 375x667, 390x844, 412x915, 844x390, 768x1024, 1366x768, 1920x1080.
- PASS: all 33 tours: 32 show price + booking card; ostionalturtles shows its quote card ("Request Exact Quote", unchanged by design). No broken images or 4xx assets; responsive variants in use. OG valid on every sitemap page except the 2 policy pages (no og:url, pre-existing, left alone). 56 blog links work without JS.
- PASS: 477-job Playwright matrix (78 pages x 7 viewports): 0 page errors, 0 failed requests, 0 HTTP errors, 0 broken images, 0 horizontal overflow, 0 stuck reveals; max CLS 0.0602; only console message = Google Maps widget blocked by the test. Targeted checks 13/13; functional 28 PASS (1 known faulty test selector: "chat widget opens" grabs the WhatsApp link).
- FAIL: blog-data.json, knowledge-validation-report.txt, hotel-knowledge-report.txt, tour-knowledge-report.txt still return 200 with old content on wildpapagayo.com (cf-cache-status DYNAMIC, `Cache-Control: public, s-maxage=604800`, Age still rising — not reset by the purge). The deployment and wild-papagayo.pages.dev return 404, and any query string gets 404. That header is not produced by this project's _headers or _worker.js, so a zone-level rule (Cache Rule / Page Rule / Cache Reserve / transform) probably holds them; the wrangler token cannot read those (403). Owner to check Cloudflare > wildpapagayo.com > Caching (Cache Rules, Cache Reserve) and Rules (Page Rules); the copies expire by themselves at the latest ~2026-11-09 (s-maxage 7 days). PHASE 5 COMPLETE is NOT marked until these return 404.
- INCIDENT 2026-11-02 22:40 UTC (read-only investigation): the stale 200s are byte-identical to the 96db1cdd assets (same ETag) but carry headers Pages only sends on *.pages.dev hosts (x-robots-tag: noindex) plus Cache-Control: public, s-maxage=604800, which no release of this project ever set. cf-cache-status DYNAMIC (the zone CDN cache is not serving them), Age = stored ~14:19 UTC (blog-data.json) and ~18:03 UTC (reports), i.e. before removal, surviving 2 deploys + the URL purge. Exact-URL key (query/encoding/double-slash all miss -> 404; client no-cache ignored; If-None-Match -> 304). Ruled out by API: no Workers, Worker routes or Worker custom domains on the account; project _worker.js runs only for /health,/assistant (_routes.json). Not readable with the wrangler token (403): rulesets/Cache Rules, Page Rules, Cache Reserve, cache level, Always Online, DNS. Most likely: a cache layer inside Cloudflare Pages custom-domain serving, which a zone URL purge does not reach; not confirmed. Expected self-expiry if s-maxage is honoured: blog-data.json ~2026-11-09 14:19 UTC, reports ~2026-11-09 18:03 UTC. No fix applied.

Deployed with `wrangler pages deploy C:\Users\Admin\wild-papagayo-backups\release-candidate-p5-20261102T203758Z --project-name wild-papagayo --branch main --commit-dirty=true` (exit 0, 478 uploaded + 430 already present; 915-file package, SHA-256 manifest next to it). Package = previous production 5b6f2634 + 95 changed files + 383 image variants; every difference machine-classified, business data (visible text, prices, links, canonicals, JSON-LD, tracking, WhatsApp, forms) identical on all 88 changed pages. deploy-package.ps1 NOT run, no IndexNow, nothing committed.
- Rollback: Cloudflare dashboard > wild-papagayo > Deployments > 5b6f2634-b1dd-4c00-b165-9560688c3d11 > Rollback (read-only copy C:\Users\Admin\wild-papagayo-backups\prod-5b6f2634-20261102). A rollback also leaves new CSS/JS at the edge for up to 24h unless purged.
- Baselines ../wild-papagayo-deploy and ../wild-papagayo-deploy-current-baseline = the deployed package (hash-identical). ../wild-papagayo-deploy.manifest.txt is the old deploy-package.ps1 output (96db1cdd build) and was not regenerated.
- Verified live: 908 served files byte-identical on 8eea9883.wild-papagayo.pages.dev; deployment URL passes all menu/Bubu checks (109/109 x2); wildpapagayo.com serves new HTML (max-age=0), 32 priced tours show price + booking (Ostional = quote card, as before), no broken images/assets, OG valid, 56 blog links work without JS, targeted checks 13/13.
- Cache history: wrangler token has no Cache Purge scope; the owner ran the Custom Purge of the 8 URLs manually (2026-11-02, before 21:48 UTC). It refreshed the 4 CSS/JS assets; the 4 removed files were not cleared (see FAIL above).
- Mobile menu (`script.src.js` initNavigation -> script.js): Escape closes + refocuses hamburger; page pinned while open (body position:fixed, `html.nav-open`), exact offset restored instantly on close (scroll-behavior forced to auto for the jump); closes when widening to >=1040px; header "scrolled" look frozen while open. `style.css`: menu panel scrolls inside itself below 1040px.
- Floating controls: one column bottom-right, no overlaps. Chat button offset is `--wpa-fab-bottom` (98px) / `--wpa-fab-bottom-m` (78px, <=600px); Bubu panel, tooltip and back-to-top (`style.css`) are computed from it. `templates/tour.html` raises the stack above the sticky booking bar at <=820px (150/146px). Bubu panel fits short landscape screens (min-width 601 + max-height 600). Tooltip sits beside the button and hides on first scroll. Bubu copy/behaviour unchanged.
- Images: `engine/image-variants.js` (sharp + ImageMagick quality gate SSIM>=0.97, PSNR>=32; 66 rejected keep the original; originals untouched) made 383 variants. `Get-SrcsetAttrs` in tour/destination/hotel generators + Blogs.html/blog-index.json `image_srcset` add srcset/sizes only where variants exist. Destination gallery reuses card sizes for photos also shown in a card (single download). Measured image bytes, all tour/hotel/destination pages + home + Blogs: 1366@1x 112.5 MB -> 55.0 MB; 390@3x 112.5 MB -> ~95.3 MB; no page heavier.
- SEO: OG/Twitter tags on category, month, profile templates + destination-finder; Blogs.html card links extension-less + static <noscript> list of published articles written by blog-generator.ps1 (BLOG-STATIC-LINKS markers). Canonicals unchanged.
- NOT changed, owner decisions: price conflicts costaricahighlights ($300 file vs $330 editorial/ops note) and oropendolahotsprings ($205 shown vs $235 in FAQ text + editorial); 41 titles >65 chars; http://www 2-hop redirect (Cloudflare setting); 2 hotel pages link ../transfers/*.html from knowledge/hotels data (in-flight work).
- Still outstanding from the live release: owner purge of blog-data.json + the 3 report .txt URLs (edge serves stale 200s; origin 404).

## AUDIT-FIXES-2026-11-02 = LIVE (deployed 2026-11-02 18:27 UTC, Cloudflare deployment 5b6f2634-b1dd-4c00-b165-9560688c3d11)

Deployed with `wrangler 4.156.0 pages deploy` from the isolated package C:UsersAdminwild-papagayo-backupselease-candidate-20261102T180152Z (deploy-package.ps1 NOT run, no IndexNow). Package = verified production 96db1cdd (== wild-papagayo-deploy, checked file by file) + 69 approved files - 4 removed (blog-data.json, knowledge-validation-report.txt, hotel-knowledge-report.txt, tour-knowledge-report.txt); 532 files. Live verification: 195/195 Playwright runs pass on wildpapagayo.com; booking cards visible on all 33 tours incl. landscape.
- Rollback: Cloudflare dashboard > wild-papagayo > Deployments > 96db1cdd-959f-4a5e-a850-941596611aec > Rollback (read-only copy: C:UsersAdminwild-papagayo-backupsprod-96db1cdd-20261101).
- Baselines refreshed from the deployed release (hash-identical): ../wild-papagayo-deploy and ../wild-papagayo-deploy-current-baseline (stale 2026-10-02 copy moved to C:UsersAdminwild-papagayo-backupscurrent-baseline-pre-20261102-stale-20261002). ../wild-papagayo-deploy.zip and its manifest still describe the 2026-11-01 build.
- OUTSTANDING (owner): purge Cloudflare edge cache for script.js, style.css, style.min.css, blog-data.json and the 3 reports (stale copies served until purge; origin already correct).
- Repo changes from this work remain UNCOMMITTED (see list below).

Five fixes from the 2026-11-02 Playwright audit; outputs regenerated with the four generators + `blog-generator.ps1 -Slug how-many-days-la-fortuna -RefreshRss` (deploy-package.ps1 NOT run). Exactly 79 files differ from the pre-fix tree:
- Reveal: `script.src.js` initReveal (threshold 0 + rootMargin 15%, reduced-motion/no-IO shows all, `html.reveal-ready` set only by JS) + `style.css` (hide only under .reveal-ready, reduced-motion rule) -> rebuilt script.js/style.min.css only; `reveal` removed from tour-summary-card + accordion-stack (templates/tour.html) and info-panel x3, ti-section, everything-included-top, tour-price-teaser x4 (tour-generator.ps1); 33 tours.
- Landing heroes: hero.image added to knowledge/landing-pages/{hotel-occidental-papagayo,waldorf-astoria-costa-rica}.json; landing-page-generator.ps1 Assert-ImagePath throws on empty/missing image (hero, tour cards, hotel cards).
- Blog: blog-generator.ps1 writes published-only blog-index.json (9 card fields) and gates rss.xml by status (draft removed); Blogs.html + single-blog.html (now redirects ?id= to blog/<slug>) read blog-index.json; deploy-package.ps1 excludes blog-data.json.
- Hotels: templates/hotel.html .hp-restaurant-grid repeat(3,minmax(0,1fr)) + joins the existing <=700px 1-column rule; 16 hotels.
- Destinations: destination-generator.ps1 BreadcrumbList Home > Destination (matches visible breadcrumb); 10-11 destination pages.
Verification: generators proven byte-deterministic before edits; output diffs proven to equal only the intended transformations; content-link-validator 0 issues; 477 local Playwright runs (7 viewports incl. 844x390, reduced motion) 0 stuck reveals/blank bands/overflow/broken images. Pre-fix snapshot + evidence: Claude scratchpad web-fix/ (session-local). Not fixed (out of scope): Escape on mobile menu, srcset, stale editorial from_price on costaricahighlights/oropendolahotsprings.

## FAMILY-HOTEL-DECISION-LAYER-001 = LIVE (deployed 2026-10-02)

Cloudflare deployment `d5c518d0` (https://d5c518d0.wild-papagayo.pages.dev), package built from prior baseline `c3886e64` (verified against live production first) + exactly 2 files overlaid: `profiles/families.html`, `hotels/hotel-riu-palace-costa-rica-hotel-en-playa-matapalo-costa-rica.html` (532 files total, 530 already uploaded). **What changed:** added the Family Hotel Decision Layer V1 narrative (`knowledge/traveler-profiles.json`, `narrative_html`, families entry) -- a property-model contrast (Riu Guanacaste's all-inclusive coastal model vs. Hacienda Guachipelín's non-all-inclusive inland ranch model), a shared children's-programming fact across multiple verified properties, hotel-specific family-room framing, and one `/transport` link, following the same pattern and evidence discipline as the Honeymoon layer. Four Seasons, Riu Palace, and Waldorf are deliberately not named in the narrative (no claim made either way). **Primary purpose:** improve family accommodation decision usefulness and AI-answer extractability using already-verified `factual_attributes`, not a new URL. No ranking or performance-improvement claim made; this establishes the observation starting point only. **Riu Palace's card notice is now source-controlled** (see the entry immediately below), not a manual patch -- confirmed present and unchanged through this deploy. `WALDORF_FAMILY_CURATION_DEBT` remains open, not addressed. `profiles/private.html` was found to have unrelated pre-existing local drift (a "Travel guides" card already different from the deployed baseline) during pre-deploy regeneration -- isolated and excluded from this package entirely, not shipped.

## RIU_PALACE_OPERATIONAL_NOTICE = SOURCE_CONTROLLED (implemented 2026-10-02, deployed with FAMILY-HOTEL-DECISION-LAYER-001)

The temporary renovation notice (hotel page + family-profile card) is no longer a manual HTML patch -- it's now driven by a new `operational_notice` object on Riu Palace's master record (`knowledge/master/hotels/hotel-riu-palace-costa-rica-hotel-en-playa-matapalo-costa-rica.json`, a sibling of `factual_attributes`, never inside it), passed through by `Convert-MasterToLegacyHotel` and rendered generically (no hotel name hardcoded) by both `hotel-generator.ps1` and `experience-profile-generator.ps1`. Both generators proved idempotent after the fix. **Why this matters:** two independent prior regenerations had silently wiped the old manual notices; this is now immune to that. **Transfer-page notice remains a separate, manually-managed caveat** (`TRANSFER_NOTICE_REMOVAL = SEPARATE_MANUAL_STEP`) -- not migrated to this mechanism, unchanged by this deploy. **Removal procedure when the property reopens:** remove `operational_notice` from the master record, run the narrow legacy sync for this hotel only, then run `hotel-generator.ps1` and `experience-profile-generator.ps1` -- both notices disappear automatically, no manual HTML cleanup needed. The transfer-page notice still needs its own separate manual removal. **Recheck target: April-May 2027**, or any official RIU reopening announcement, whichever comes first.

## TEMPORARY_CONTENT_MAINTENANCE = RIU_PALACE_RENOVATION_2026_2027 (implemented 2026-10-02)

Cloudflare deployment `c3886e64` (https://c3886e64.wild-papagayo.pages.dev), package built from prior baseline (`cea97e96`, verified against live production first) + exactly 3 files overlaid: `hotels/hotel-riu-palace-costa-rica-hotel-en-playa-matapalo-costa-rica.html`, `profiles/families.html`, `transfers/liberia-airport-to-riu-palace-costa-rica.html` (532 files total, 529 already uploaded). **Reason:** official-source research confirmed Hotel Riu Palace Costa Rica is currently closed for renovation (the hotel's own official RIU page carries the live notice "Hotel under renovation. Reopening: April 2027"; RIU's own blog, Jan 2026, independently confirms the renovation is planned to start summer 2026 and reopen in 2027; a third-party trade article gives specific but RIU-uncorroborated dates of 2026-08-31 start / 2027-04-24 reopen). Added a small, non-alarmist temporary notice to all three traveler-facing surfaces, reusing each page's own existing color palette (no new CSS system): the hotel page's own notice sits before its "Book on Expedia" CTA so a traveler sees it before interpreting the hotel as bookable; the family-profile card keeps its existing recommendation and permanent description unchanged, with the notice added as a small line within the same card; the transfer-landing page's notice sits in the hero, before its booking CTA. No specific reopening date published anywhere (deliberately -- the official date could move, and a dated note would itself go stale) -- wording is "currently closed for renovation; confirm reopening status before booking" or the semantic equivalent. **No change to:** `factual_attributes`/hotel knowledge (confirmed: this is a temporary operational concern, not a durable hotel fact), schema, generators, Bubu (`functions/assistant-knowledge.json` confirmed byte-identical, same hash as every prior check this session), transfer page canonical/title/meta/H1/JSON-LD/FAQ/pricing/route semantics, the Expedia affiliate link, or any other hotel card. One pre-existing, unrelated local drift was found and isolated before packaging: the Riu Palace hotel page's local working copy had already drifted from the active baseline (an SEO-title update already present in its own `knowledge/master/hotels/...json` plus a "Travel Insights" card-section refresh, both legitimate and already-approved-looking but not part of this task) -- reverted that file to exact baseline bytes first, then applied only the authorized notice on top, confirmed via byte-level reconstruction that the final package diff is the notice and nothing else. IndexNow: submitted exactly the 3 changed URLs, status 200. Baseline refreshed in place (one active baseline maintained); temporary deploy package removed after refresh. **Recheck target: ~April-May 2027**, or immediately upon any official RIU reopening announcement -- at that point, remove the three notices (the underlying family/positioning/all-inclusive/beach facts researched for this hotel remain valid and were not touched).

## HONEYMOON-ACCOMMODATION-DECISION-LAYER-001 = LIVE (deployed 2026-10-02)

Cloudflare deployment `cea97e96` (https://cea97e96.wild-papagayo.pages.dev), package built from prior baseline (verified against live production first, byte-identical) + exactly 1 regenerated file (`profiles/honeymoon.html`, 532 files total, 531 already uploaded). Extended the existing honeymoon narrative mechanism (`knowledge/traveler-profiles.json`, `narrative_html`, honeymoon entry only) with a V1 accommodation-decision layer: one-base-vs-two-settings accommodation implication, the hotel-marketing-vs-editorial-curation distinction (a hotel need not market itself for honeymoons to be curated as one), adults-only framed as a preference with explicit six-property scope (Occidental Papagayo is the only one of the six `factual_attributes`-verified hotels confirmed adults-only), a neutral resort-time-vs-exploration framing with an internal link to `/transport` using the approved general-coverage sentence, and a practical-details callout (Occidental=all-inclusive/Suitree=not; beach relationship for Occidental/Four Seasons/Waldorf/Suitree/Borinquen, all already-`factual_attributes`-established facts). No new URL, no FAQ schema, no change to any hotel JSON/`factual_attributes`/`best_for`/generator/validator. Confirmed byte-identical: all 7 other profile pages, both Bubu knowledge outputs, all 6 pilot hotels' master+legacy JSON, and 4 spot-checked protected/unrelated live surfaces (`profiles/couples`, `profiles/families`, `transport.html`, `/transfers/liberia-airport-to-riu-guanacaste`) via Cloudflare-email-obfuscation-normalized diff. `llms.txt` showed a diff against the *local working-copy* file only -- the deployed baseline's own `llms.txt` was confirmed byte-identical to live, so this was pre-existing local/baseline drift unrelated to this deploy, not a regression. IndexNow: submitted exactly 1 URL (`https://wildpapagayo.com/profiles/honeymoon`) via a scoped single-URL call reusing the existing published key, status 200 -- did not run the bulk `indexnow-submit.ps1` (which submits the entire sitemap) to avoid notifying unrelated URLs. Baseline refreshed in place (one active baseline maintained); temporary deploy package removed after refresh.

## RIU-MULTIGENERATIONAL-PLANNING-LAYER-001 = LIVE (deployed 2026-10-02)

Cloudflare deployment `03b346ce` (https://03b346ce.wild-papagayo.pages.dev), package built from prior baseline `2ff90141` + exactly 3 regenerated files (`tours/paloverderiverboattour.html`, `blog/best-tours-from-riu-guanacaste-local-recommendations.html`, `blog/best-tours-from-riu-palace-costa-rica.html`). **Palo Verde River Boat minimum age corrected 8 -> 2, owner-confirmed 2026-10-02** -- resolved the long-standing `PALO_VERDE_MINIMUM_AGE_CONFLICT` source-of-truth debt (flat field, FAQ answer prose, quick-facts pill label, and the derived `intelligence.minimum_age` all now consistently read 2; zero remaining age-8 references anywhere in source or rendered output). Added 4 multigenerational-planning FAQs to each Riu Guanacaste and Riu Palace Costa Rica Best-Tours article (young children, grandparent/gentler-day framing using only existing duration/difficulty facts -- no accessibility/medical claims, a rest-day pacing note, a cautious December/high-season booking note) plus one direct internal link per article to its own protected transfer landing page. FAQ/schema parity confirmed 14/14 (Guanacaste) and 13/13 (Palace). Nightlife content, tour inventory, and canonical/title/H1 on both articles unchanged. Protected pages (`transport.html`, both `/transfers/liberia-airport-to-riu-*` landing pages, `llms.txt`, `sitemap.xml`, `rss.xml`) and the `BLOG-BABY-NO-CAR-001`-protected baby articles confirmed untouched throughout, including through two full regenerate/diff/restore passes to isolate unrelated pre-existing local drift (same `waterfallpumas.html` / `dry-season-in-guanacaste-what-to-expect.html` drift pattern as the Honeymoon-layer task, neither shipped).

**Real rendered QA this task** (headless Chrome, confirmed genuine viewport widths via PNG pixel inspection, not structural-only): 1280px -- clean, no overflow, all new FAQs and the transfer link render correctly. 390px -- confirmed a **pre-existing, site-wide right-edge text-clipping bug** affecting the shared blog-article and tour-page templates at narrow viewports (headings/body text cut off rather than wrapping), independently reproduced on an untouched control page (`blog/liberia-airport-transfer-guide.html`) -- not introduced or worsened by this task, logged as open debt (see below), did not block this deploy per owner decision.

Open technical debt recorded, not fixed this task (expanding scope was explicitly declined):
- `SITE_WIDE_390PX_RIGHT_EDGE_CLIPPING` -- shared CSS/template issue, observed on both the blog-article and tour-page templates, needs its own dedicated investigation.
- `PALO_VERDE_INTELLIGENCE_BUILDER_SCOPED_UPDATE` -- `tour-intelligence-builder.ps1` has no mode to update a single `intelligence.*` field; running it (even with `-TourId`) recomputes `energy_level`, `primary_category` and every `traveler_scores` value from current algorithm logic. `intelligence.minimum_age` was hand-patched to stay in sync with the authoritative flat field instead of running the builder.

`CHILD_SEAT_TRANSPORT_LAYER` and `MULTI_LEG_TRANSPORT_LAYER` remain deferred to the already-planned `/transport` update (same 2026-10-18 / ~2026-10-19 checkpoints). Old baseline kept at `../wild-papagayo-deploy-current-baseline.pre-riu-layer-backup` for rollback. No IndexNow call (no established policy covers a surgical manual deploy; see the Honeymoon-layer entry below for the same reasoning).

## HONEYMOON-EXPERIENCE-LAYER-001 = LIVE (deployed 2026-10-02)

Cloudflare deployment `2ff90141` (https://2ff90141.wild-papagayo.pages.dev), package built from prior baseline `05a54234` + exactly 2 regenerated files (`profiles/honeymoon.html`, `destinations/guanacaste.html`, 523 files total, 521 already uploaded). Added a conditional narrative layer (`knowledge/traveler-profiles.json` `narrative_html` field, honeymoon entry only; `templates/profile.html` + `experience-profile-generator.ps1` render it only when present -- confirmed byte-identical on all other 7 profiles) stating the "don't plan a honeymoon like a sightseeing itinerary" contrast principle, linking to `destinations/la-fortuna` and `destinations/guanacaste`. Added one honeymoon-specific FAQ to `knowledge/destinations/guanacaste.json` (visible + FAQPage schema, same source). Tagged the existing `la-fortuna-to-playa-flamingo-without-the-monkey-trail` blog article with `"honeymoon"` in `blog-data.json`, which now surfaces it on the Honeymoon profile's Travel Guides section in place of the generic fallback card (zero effect on the article's own page -- it has a `recommended_tour_ids` editorial pin that bypasses profile-tag scoring). Intentionally NOT changed: La Fortuna FAQ (would duplicate the existing "worth visiting from Guanacaste" answer), `how-many-days-la-fortuna` tag (content is pacing-neutral, no honeymoon-specific value), the shared "in Guanacaste & Arenal" H1/title/schema wording baked into `templates/profile.html` + `experience-profile-generator.ps1` across all 8 profiles (separate cross-profile architecture decision, deferred), `transport.html` (deferred to the separate transportation architecture update). Approved 3 tours/3 destinations/3 hotels on the Honeymoon profile unchanged. Regenerating surfaced unrelated pre-existing local drift on 10 other destination pages, `blog/dry-season-in-guanacaste-what-to-expect.html` and `rss.xml` (none caused by this task, isolated via revert-and-compare, restored where a clean backup existed; `rss.xml` could not be restored -- no pre-task backup existed -- but confirmed to have zero causal relationship to this task's edits). Old baseline kept at `../wild-papagayo-deploy-current-baseline.pre-honeymoon-layer-backup` for rollback.

## HOME-SEO-H1-001 = LIVE (deployed 2026-09-26)

Cloudflare deployment `9d078247`, package `../wild-papagayo-deploy-home-h1-001` = `destcards-001` + `index.html` only (532 files, 1 changed). Home H1 now "Private Tours & Transfers from Papagayo, Costa Rica"; "Discover Costa Rica, Your Way." moved to the hero eyebrow. JSON-LD: FAQPage and paymentAccepted removed, logo 450x226, offer prices 275/225/250. Head/title/canonical/OG/Twitter, links, CTAs, sitemap, robots unchanged. GA `content_name` for home events now uses the new H1. Note: local `sitemap.xml` is still drifted vs production; build future packages from the latest production package.

## SUPPLIER-POLICY-AUDIT-001 = AUDIT ONLY (2026-09-26)

20 external-supplier tours checked against first-party terms only (no stored contracts/rates exist in the repo). RED: `congotrail`, `congotrailcanopy` (no refunds/credit-only at Congo Trail). YELLOW: `laleona` (two competing official sites, reschedule makes booking non-refundable on one). GREEN (48 h suppliers): `haciendaguachipelin`, Selvatura/Mistico-based tours. 13 UNKNOWN - contact list in the report. Standard 72 h policy and website unchanged. Report: `seo-intelligence/reports/supplier-cancellation-policy-audit.md`.

## DEST-IMPORT-SAFETY-001 = IMPLEMENTED LOCALLY (2026-09-26)

`destination-import-url.ps1`: existing record aborts (exit 1, before any API call) unless `-Update`; `-Update` = backup to `knowledge/backups/destinations/` + narrow merge of 10 text fields + verification.source/note, status never changed; published/disabled also need `-AllowNonDraft`. 9/9 scratch tests pass; create output unchanged; CMS unaffected (existing id now returns an error). Report `seo-intelligence/reports/destination-import-safety.md`. `hotel-import-url.ps1` already protected via `hotel-create.ps1`.

## DEST-IMPORT-AUDIT-001 = AUDIT ONLY (2026-09-26)

`destination-import-url.ps1` has no existence check: re-running it (or the CMS import action) on an existing destination fully replaces the record - published becomes draft, hero_image reset, experience_scores/restaurants/gallery/testimonials deleted, no backup. **Do not run it on existing ids.** Proposed: abort-on-existing + explicit `-Update` (narrow merge, backup, status preserved). Report: `seo-intelligence/reports/destination-import-overwrite-audit.md`. Nothing changed.

## DEST-CARDS-FINAL-001 = LIVE (deployed 2026-09-26)

Cloudflare deployment `ffbfc8a4` (https://ffbfc8a4.wild-papagayo.pages.dev), package `../wild-papagayo-deploy-destcards-001` = `destbubu-001` + 5 regenerated destination pages (guanacaste 26, la-fortuna 14, playa-hermosa 6, papagayo 35, playa-coco 9 blog links; tamarindo unchanged at 3). Pure additions of 19 blog cards, 0 removals; sitemap, llms.txt, Bubu, blog-data.json, blog pages and other destination pages unchanged. Validated on the unique URL and wildpapagayo.com. No indexing requests. (Older entry below described the prepared package.)

## DEST-CARDS-FINAL-001 = PACKAGE PREPARED, NOT DEPLOYED (2026-09-26)

`liberia-airport-transfer-guide` now has `"status": "published"` (strict destination-card gate kept). Scratch pages give the approved counts (guanacaste 26, la-fortuna 14, playa-hermosa 6, papagayo 35, playa-coco 9, tamarindo 3; tamarindo byte-identical to production). Candidate package `../wild-papagayo-deploy-destcards-001` = `destbubu-001` + 5 regenerated destination pages only (guanacaste, la-fortuna, playa-hermosa, papagayo, playa-coco); changes are pure additions of 19 blog cards, 0 removals. Awaiting explicit deploy approval.

## DEST-BLOG-METADATA-001 = LOCAL ONLY, NOT DEPLOYED (2026-09-26)

Approved `blog-data.json` destination cleanup applied (car guide, Playa Hermosa kids, Waldorf -> playa-hermosa, dry-season -> guanacaste, `playas-del-coco` -> `playa-coco`) and a strict `status == published` article gate added to `destination-generator.ps1`. Scratch pages equal production apart from approved cards. Open: the legacy record `liberia-airport-transfer-guide` has no `status`, so the strict gate drops its card from guanacaste/papagayo/playa-coco/tamarindo until it gets `"status": "published"` (not applied: outside the approved list). Report: `seo-intelligence/reports/destination-blog-metadata-cleanup.md`.

## DEST-BLOG-CARD-DRIFT-AUDIT-001 = AUDIT ONLY (2026-09-26)

Extra blog cards on local guanacaste/la-fortuna/playa-hermosa/papagayo pages are 17 valid published+live articles (none draft); production pages are stale. Generator has no cap/ranking/status gate (Papagayo: 38 tagged, 39 cards). 3 weak/incorrect Papagayo associations + a Waldorf tag mismatch proposed for metadata fixes; production `blog-data.json` is stale (38 vs 57) and the 17 live articles have 0 inbound internal links in production. Report: `seo-intelligence/reports/destination-blog-card-drift-audit.md`. Nothing changed or deployed.

## DEST-HOTEL-GATE-001 = IMPLEMENTED LOCALLY, NO DEPLOY NEEDED (2026-09-26)

`destination-generator.ps1` hotel loader (`knowledge/master/hotels`, `workflow.status`) now requires `published` (was: only skipped
`disabled`). New playa-coco output equals production; real local `destinations/playa-coco.html` still has the stale draft-hotel
link (not regenerated). Remaining un-gated public consumers are latent only: `blog-generator` (hotel name in CTA text) and
`landing-page-generator` (config-driven, all ids published). Report: `seo-intelligence/reports/destination-hotel-gate.md`.

## PROFILE-HOTEL-GATE-001 = IMPLEMENTED LOCALLY, NO DEPLOY NEEDED (2026-09-26)

`experience-profile-generator.ps1` hotel loader (`knowledge/hotels`, flat `status`) now requires `published`. Gated output equals
production for all 8 profile hotel sections (local `profiles/` files are stale; do not ship). Open: `destination-generator.ps1`
hotel cards use `workflow.status -eq 'disabled'` only, so local `destinations/playa-coco.html` links draft
`bahia-pez-vela-resort` (not in production). Report: `seo-intelligence/reports/profile-hotel-gate.md`.

## DEST-GATES-001 = IMPLEMENTED LOCALLY, NO DEPLOY NEEDED (2026-09-26)

Strict `status == "published"` destination gate now in `destination-generator`, `month-generator`, `llms-txt-generator`,
`sitemap-generator` (record-based for the destinations dir), `destination-finder-generator`, `experience-profile-generator`,
`hotel-generator` and `hotels-index-generator` (destination links only); `destination-import-url` creates records as `draft`.
Published outputs byte-identical; `playa-conchal` 0 month cards, 0 sitemap/llms entries. Open, unfixed: `experience-profile-generator`
hotel loader has no publication gate (would recommend draft `bahia-pez-vela-resort` on `profiles/groups.html`). Report:
`seo-intelligence/reports/destination-publication-gates-implementation.md`, diff `destination-publication-gates.diff`.

## DEST-BUBU-FIX-001 = LIVE (deployed 2026-09-26)

Cloudflare deployment `e852512a` (https://e852512a.wild-papagayo.pages.dev), package `../wild-papagayo-deploy-destbubu-001`
(= pubstate-001 + `functions/assistant-knowledge.json` and rebuilt `_worker.js` only; 532 files). Bubu destinations 12 -> 11:
`playa-conchal` removed; live Bubu no longer links `/destinations/playa-conchal`. Local source changes: `status` line added to
all 12 `knowledge/destinations/*.json` (11 `published`, `playa-conchal` `draft`, one line each, formatting preserved) and a strict
`status -eq 'published'` gate in `assistant-knowledge-generator.ps1`'s destinations loop. **Not yet applied** (still open from
the audit): gates in `destination-generator`, `month-generator`, `llms-txt-generator`, `sitemap-generator`, finder/profiles,
hotel links, and the import script default. Do not regenerate months/sitemap/llms.txt until those are gated.

## DESTINATION-PIPELINE-AUDIT-001 = AUDIT ONLY (2026-09-26)

Destinations have no status field; every generator treats a record as published. `playa-conchal` (created 2026-09-25,
INCOMPLETE DRAFT: no experience_scores/gallery/restaurants/testimonials, generic hero, dead `playa-flamingo` nearby link)
**is live-leaking in production Bubu**, which sends users to `/destinations/playa-conchal` (404). Future leak paths:
`llms.txt`, sitemap, all 12 month pages (empty `best_season`), hotel links. Proposed: flat `status` + strict `published` gate +
migration of the 12 records; not applied. Report: `seo-intelligence/reports/destination-publication-pipeline-audit.md`.

## PUBSTATE-FIXES-DEPLOY-001 = LIVE (deployed 2026-09-26)

Cloudflare deployment `bec0c53c` (https://bec0c53c.wild-papagayo.pages.dev), package `../wild-papagayo-deploy-pubstate-001`
(= `wild-papagayo-deploy-policy-001` + 2 files: `functions/assistant-knowledge.json` and rebuilt `_worker.js`; 532 files,
0 added/removed). Effect: Bubu's hotel knowledge 19 -> 16 (Bahia Pez Vela, W Costa Rica Resort, Westin long-slug removed).
Production `hotels.html`, the 16 hotel pages, `llms.txt`, `sitemap.xml` were already correct and are byte-identical, so they were
deliberately NOT changed (local `hotels.html` differs from production only by favicon-formatting drift). Blog/hotel generator
gates and `blog-data.json`/`knowledge/*` status fixes are source-only (not deployed artifacts). Not included: `playa-conchal`
destination (404, still open), `llms.txt`/`sitemap.xml` regeneration, unrelated drift. No indexing requests.

## HOTEL-PIPELINE-PAGE-INDEX-001 = FIXED LOCALLY (deployed via PUBSTATE-FIXES-DEPLOY-001, 2026-09-26)

`hotel-generator.ps1` and `hotels-index-generator.ps1` now require `status == "published"` on `knowledge/hotels`
records (was: only excluded literal `"disabled"`). `knowledge/hotels/{bahia-pez-vela-resort,
the-westin-reserva-conchal-an-all-inclusive-golf-resort-spa}.json`: `status` `"published"` -> `"draft"` (only that
field; `w-costa-rica-resort` was already `"draft"`, left alone). Regenerated `hotels/*.html` (19 -> 16 pages, all
16 byte-identical to before) and `hotels.html` (16 hotels, only the ItemList renumber + removal of the one-hotel
"Playa Conchal" group changed). Deleted the 3 stale local hotel pages the fixed gate no longer produces
(`bahia-pez-vela-resort.html`, `w-costa-rica-resort.html`, the Westin long-slug page) so a future wholesale
folder copy can't resurrect them. `sitemap.xml`, `llms.txt`, Bubu's knowledge: confirmed byte-identical, not
regenerated (out of scope for this pass). Full validation in
`seo-intelligence/reports/hotel-pipeline-page-index-fix.md`. Both hotel knowledge directories (`knowledge/hotels`,
`knowledge/master/hotels`) now agree that all three are non-published; not merged. Not deployed; no indexing
requests.

## HOTEL-PIPELINE-STRICT-GATE-001 = FIXED LOCALLY, NOT DEPLOYED (2026-09-26)

`assistant-knowledge-generator.ps1` and `llms-txt-generator.ps1` now require `workflow.status == "published"` on
`knowledge/master/hotels` records (was: no gate at all / only excluded literal `"disabled"`). The gate alone
didn't change anything (all 3 broken hotels' own master records already said `"published"`), so the owner was
asked and chose to correct the data: `workflow.status` on `bahia-pez-vela-resort`, `w-costa-rica-resort`, and
`the-westin-reserva-conchal-an-all-inclusive-golf-resort-spa` in `knowledge/master/hotels` is now `"draft"` (only
that one field changed in each record). **Confirmed result: Bubu hotels 19 -> 16, `llms.txt` hotels 17 -> 16, all
3 broken hotels excluded, all 16 real hotels remain, no other section of either file changed.** `hotels.html`,
`sitemap.xml`, `knowledge/hotels`, `hotel-generator.ps1`, `hotels-index-generator.ps1` untouched. Full report incl.
an exhaustive `knowledge/hotels` status matrix (same gate would be safe there too, and would additionally catch
`w-costa-rica-resort` specifically) in `seo-intelligence/reports/hotel-pipeline-strict-gate-fix.md`. Not deployed;
no indexing requests.

## HOTEL-PIPELINE-AUDIT-001 = AUDIT ONLY, NOTHING FIXED OR DEPLOYED (2026-09-26)

**Full audit of the hotel publication pipeline.** Confirms the Bahía Pez Vela / W Costa Rica issue is one instance
of a broader gap: `assistant-knowledge-generator.ps1`'s hotel loop (reads `knowledge/master/hotels`) has **no
status gate at all**; `hotel-generator.ps1`/`hotels-index-generator.ps1`/`llms-txt-generator.ps1` only exclude the
literal value `"disabled"`, not "anything other than published." **Found a third already-broken hotel that was
not previously known**: `the-westin-reserva-conchal-an-all-inclusive-golf-resort-spa` -- 404 live, but present in
the currently-deployed production Bubu knowledge right now (confirmed against both the live site and the
`wild-papagayo-deploy-bubu-production` reference snapshot, whose `hotels/` folder has only 16 real pages against
19 in its own already-deployed knowledge file). No currently-live page on the actual website links to any of the
3 broken hotels; the only live exposure is Bubu naming/linking them in chat. Full inventory, source-of-truth map,
conflict report and a proposed (not-yet-applied) fix are in
`seo-intelligence/reports/hotel-publication-pipeline-audit.md`. One test run of `hotels-index-generator.ps1` was
done and immediately reverted -- `hotels.html` is confirmed byte-identical to before this audit.

## BAHIA-PEZ-VELA-PUBSTATE-001 = FIXED LOCALLY, NOT DEPLOYED (2026-09-26)

**Root cause found and fixed for why the undeployed Bahía Pez Vela blog article kept re-entering Bubu's
knowledge:** `blog-generator.ps1` and `assistant-knowledge-generator.ps1` never read `blog-data.json`'s `status`
field at all -- every record was generated/included regardless of status, unlike hotels/tours/destinations which
already have a real status gate. Fixed: both generators now skip an article whose `status` isn't `"published"`;
the Bahía Pez Vela record's status is now `"draft"`; the stale local `blog/best-tours-from-bahia-pez-vela-resort.html`
was deleted (it 404s in production and was never deployed). Regenerated Bubu knowledge locally: 56 articles (was
57), byte-identical to what's already live in production for every other section. No other `"published"` blog
record 404s in production. Full report: `seo-intelligence/reports/bahia-pez-vela-publication-state-audit.md`.

**Separate, more urgent finding from the same audit, NOT fixed:** Bubu's knowledge -- already live in production
-- includes two hotels whose pages both 404: `bahia-pez-vela-resort` and `w-costa-rica-resort`. Root cause is
in the hotel pipeline (two out-of-sync knowledge directories, `knowledge/hotels` vs `knowledge/master/hotels`,
and a status gate that only excludes literal `"disabled"`, not `"draft"`). Needs its own dedicated audit --
do not run `hotels-index-generator.ps1` without expecting it to add both broken links (confirmed by testing;
reverted).

## BOOKING-POLICY-72H-001 = LIVE (deployed 2026-09-26)

**Sitewide booking / payment / cancellation / refund policy, owner-approved and deployed 2026-09-26.**
Cloudflare deployment `3078cff7` (https://3078cff7.wild-papagayo.pages.dev), branch `main`, from
`../wild-papagayo-deploy-policy-001`. Validated on the deployment URL and on wildpapagayo.com: all 179 HTML pages
identical to the package (apart from Cloudflare email obfuscation and analytics beacon), every policy check
passes, Bubu answers all 7 required policy questions correctly. No indexing requests. Report:
`seo-intelligence/reports/booking-policy-production-validation.md`. Follow-ups (not in this deploy):
`seo-intelligence/reports/booking-policy-follow-ups.md`. Standard: 25% deposit; 75% due no later than 72 h before; full payment for bookings
within 72 h; cancellations within 72 h and no-shows non-refundable subject to mandatory consumer rights;
guest-requested refunds >72 h = the refundable amount paid less applicable non-recoverable payment-processing
costs when legally permitted (Compra Click BAC: 2.50% not returned + US$8 per refund); date changes >72 h
subject to availability, no automatic right within 72 h; Wild Papagayo cancels -> 100% refund, costs absorbed;
normal rain does not automatically qualify; multi-day/special services = written conditions before payment.

- **Deploy package:** `../wild-papagayo-deploy-policy-001` = `../wild-papagayo-deploy-bubu-production` (the true
  production baseline since deployment 889c8140; `current-baseline` is one release behind for functions/) +
  approved changes only. 180 files differ: 178 HTML pages (all except `offline.html`),
  `functions/assistant-knowledge.json` and `_worker.js`; `_routes.json` rebuilt but byte-identical; no files added
  or removed. The `netlify/` knowledge copy is deliberately left at production.
- **Sources edited:** `politicasdecancelacion.html` (canonical, retitled "Booking, Payment, Cancellation & Refund
  Policy", URL unchanged), `Terminosycondiciones.html`, `guides.html` (visible + JSON-LD), `Bookingform.html`,
  `transport.html`, `paquete.html`, `templates/tour.html` (trust strip + footer), `templates/components/footer.html`,
  footer strings in `blog-generator.ps1` / `tool-finder-generator.ps1` / `hotels-index-generator.ps1` /
  `destination-finder-generator.ps1`, 33 `knowledge/tours/*.json` (reservation_policy + cancel FAQ only),
  `knowledge/landing-pages/liberia-airport-to-la-fortuna.json`, `assistant-knowledge-generator.ps1`
  (`company.booking_policy`), ~21 hand-edited root pages (footer label).
- **Regenerated:** `tour-generator.ps1` (33) and `landing-page-generator.ps1` (11). Both were first proven
  idempotent with the old sources; every other page got the identical footer-label replacement directly.
- **Bubu:** knowledge = production knowledge + `booking_policy` (the regenerated file also pulled in the undeployed
  Bahia Pez Vela article; that entry was removed so Bubu does not link to a 404). `functions/assistant.js`
  unchanged; rebuilt `_worker.js` differs from production only in the knowledge data. Tested locally with the
  compiled worker (9 prompts). Final pre-deploy correction: `cancellation_more_than_72_hours` now reads
  "receive a refund of the refundable amount paid, ..." (Bubu had paraphrased it as "the amount paid").
- **Approved supplier-specific clauses:** Ostional and Rio Celeste keep their supplier reason, window now 72 h;
  Tubing Rio Celeste river-colour rule unchanged. External-supplier tours flagged for verification in
  `seo-intelligence/reports/supplier-policy-verification.md`.
- **Known, not fixed:** `blog-data.json` still marks the undeployed Bahia Pez Vela article "published", so the next
  `assistant-knowledge-generator.ps1` run will re-add it to Bubu's knowledge; 8 pre-existing homepage/transport
  FAQ schema answers differ from their visible text (unrelated, identical in production).
- Record: `seo-intelligence/reports/booking-policy-implementation-report.md`. Change set:
  `seo-intelligence/reports/booking-policy-change-set.md`.

## BUBU-PROMPT-EVOLUTION-001 = LIVE (deployed 2026-09-25, approx. 23:00 CST)

**Conservative Bubu prompt improvement + knowledge refresh -- no new tools, no architecture change.**
Cloudflare deployment `889c8140` (https://889c8140.wild-papagayo.pages.dev), branch `main`. Files changed:
`functions/assistant.js` (SYSTEM_PROMPT only -- added explicit anti-hallucination/no-discount/no-availability
language, children-age discovery guidance, style guidance against repetitive openers, and a prompt-injection
defense section; `BUBU_META`'s 13 fields/format/wrapper are byte-identical to before), `functions/assistant-knowledge.json`
(regenerated from source via `assistant-knowledge-generator.ps1` -- now 19 hotels, includes Bahia Pez Vela
Resort and W Costa Rica Resort - Playa Conchal, both previously missing from the assistant's knowledge),
`_worker.js` + `_routes.json` (rebuilt via `npx wrangler pages functions build`, per the new permanent rule
in `CLAUDE.md`'s Deployment safety rules section).

- Staged first at `bubu-staging` branch (deployment `949d4dba`) and validated with 9 functional test
  cases before promoting to `main`. A real deploy bug was caught and fixed during staging: the first
  staging attempt copied only loose `functions/*.js` files, but Cloudflare Pages ignores `functions/`
  entirely when a `_worker.js` exists at the deploy root -- the stale baseline `_worker.js` kept serving
  the OLD 17-hotel knowledge until rebuilt properly. See `CLAUDE.md` for the permanent rule this produced.
- Post-deploy validation on the immutable deployment URL (before relying on the custom domain): `/health`
  200, CORS correct for allowed/disallowed origins, Bahia Pez Vela and W Costa Rica both recognized
  correctly (no invented prices, no hotel confusion), 5/5 reduced regression tests passed (discovery,
  availability, discount, booking, prompt-injection), `BUBU_META` confirmed never visible to the client.
- **Open observation, not a regression:** one of four memory multi-turn tests on production showed the
  hotel from turn 1 not being recalled in turn 2 (asked again); three other identical-pattern tests (on
  fresh conversation IDs) succeeded normally. The KV memory read/write code itself was not touched by
  this deploy -- most likely Cloudflare KV's own eventual-consistency window, not something this change
  introduced. Worth knowing about if a similar report ever comes from a real visitor, not treated as a
  blocking bug.
- D1 lead-row creation was not directly inspected this phase (no binding/database ID available in this
  session to query it read-only) -- functional behavior (correct `needs_human`-driving responses on
  discount/booking requests) was confirmed instead. Flagged as a follow-up if anyone wants to confirm the
  D1 side directly.
- Production (`wildpapagayo.com`) was live and unaffected by staging deploys throughout; this is the
  first deploy of this phase to touch `main`.

## 4X4-MONKEY-TRAIL-MICRO-001 = LIVE (deployed 2026-09-24, approx. 13:22 CST / 19:22 UTC)

**Micro-update, one new body section on one existing article — no new URL.**
`/blog/la-fortuna-to-playa-flamingo-without-the-monkey-trail` gained one new H2, "Do You Need a 4x4 for
This Route?" (196 words, 3 paragraphs), inserted immediately after the existing "Why Do Some Travelers
Avoid the Monkey Trail?" section.

- Preceded by `seo-intelligence/reports/costa-rica-4x4-opportunity-analysis.md`
  (`ADD_SECTION_EXISTING`) and `costa-rica-4x4-existing-page-micro-update-design.md`
  (`READY_FOR_MICRO_UPDATE`). Found the article already had a nuanced FAQ answer on this topic
  ("four-wheel-drive... not normally required for the standard route") but no supporting body-text
  section connecting it to the already-published Monkey Trail risk narrative.
- Every claim in the new section is either already-published first-party content reused faithfully
  (the "4WD not normally required" / "higher-clearance more comfortable" distinction, the Monkey Trail
  river-crossing risk, the hedged "rental-car insurance may not cover damage... driving through rivers"
  wording) or generic, unfalsifiable travel advice (ask your accommodation about last-mile access). The
  insurance wording was explicitly audited and left unchanged ("may not cover," never strengthened to
  "does not"/"will not").
- Source-of-truth edit only: `blog-data.json`'s `content_block_2` field for article id 33 (slug
  `la-fortuna-to-playa-flamingo-without-the-monkey-trail`), regenerated via
  `blog-generator.ps1 -Slug la-fortuna-to-playa-flamingo-without-the-monkey-trail` (single-article mode).
  Diff-verified: exactly 1 production file changed, exactly 2 lines differ (TOC entry + body section) —
  title, H1, canonical, meta description, and FAQPage schema all confirmed byte/semantically identical
  to the prior baseline. No new FAQ (the existing "four-wheel-drive" FAQ was left untouched, per the
  design's `FAQ_NOT_NEEDED` verdict). No new internal link, no new CTA (CTA count unchanged at 5).
- Rendered-layout verified via real headless-Chrome screenshots at 390/430/1280px — correct heading
  hierarchy, correct insertion position (item 4 of 8 in the table of contents), no overflow/collision
  beyond the same sitewide narrow-viewport text-wrapping already present on every other page.
- Deployment `89d58a90`, verified HTTP 200 on both the deployment URL and `wildpapagayo.com`. Protected
  pages reconfirmed live/unaffected: `costa-rica-without-a-car-guide`, `destinations/guanacaste`,
  `tours/hikingrinconnationalpark` (EXP-001), `tours/slothadventure` (BIJAGUA-SLOTH-001). `llms.txt`
  unaffected (not part of this deploy — no new URL was created).
- External cost this implementation: $0.00. (Separately, $0.0612 was spent during the earlier
  *research* phase for this opportunity — recorded under its own cost-report entry, not re-counted
  here.)
- **Observation checkpoints: Day 7 (~2026-10-01), Day 14 (~2026-10-08), Day 28 (~2026-10-22).** Per
  standing practice, freeze this page during the observation window unless a real defect is found — do
  not make another SEO tweak to this URL before Day 28. Full detail:
  `seo-intelligence/data/processed/4x4-monkey-trail-micro-001-observation-record.json`.

## GUANACASTE-WHERE-TO-STAY-001 = LIVE (deployed 2026-09-24, approx. 11:57 CST / 17:57 UTC)

**Content/architecture update to `destinations/guanacaste.html` — not a content experiment, but has
observation checkpoints since it targets a real (if weak) existing search intent.** Corrected the
page's existing "Where to Stay in Guanacaste" section and "best base" FAQ, which previously conflated
excursion destinations (Rincón de la Vieja, Monteverde) with lodging bases and silently excluded Playas
del Coco (zero mapped hotels in the legacy hotel-presence filter). Added an explicit, hotel-mapping-
independent `stay_bases` field to `knowledge/destinations/guanacaste.json` (Papagayo, Playas del Coco,
Playa Hermosa, Tamarindo, each with an owner-confirmed without-a-car note) and a small additive branch
in `destination-generator.ps1` — the pre-existing `nearby` field and its "Nearby destinations" section
are untouched, and Rincón de la Vieja/Monteverde still legitimately appear there.

- **A real regression was caught and fixed before deploy**: a PowerShell `@($null).Count` gotcha caused
  every destination *without* `stay_bases` to silently lose its own legacy section — caught by diffing
  all 11 regenerated destination pages against the live baseline, not just the intended one.
- **Unrelated pre-existing drift was found and deliberately excluded from the deploy**: `la-fortuna`,
  `papagayo`, and `playa-hermosa` destination pages' "Travel insights" cards had picked up already-
  published blog articles not yet reflected in the baseline snapshot — real, legitimate, but out of this
  task's scope. `destinations/guanacaste.html` itself was rebuilt via a byte-precise surgical patch
  (baseline + only the 3 intended regions: FAQ schema, visible FAQ, Where-to-Stay section) so its own
  Travel-insights section also stayed unchanged. **Final deploy: exactly 1 file** (`destinations/
  guanacaste.html`), verified via `diff -rq` against the 522-file baseline.
- Deployment `e8f9c583`, verified HTTP 200 on both the deployment URL and `wildpapagayo.com`. FAQ
  visible/schema sync exact (6/6). Canonical/title/H1/meta unchanged. No new schema types. Rendered-
  layout verified via real headless-Chrome screenshots at 390/430/1280px (table + cards render
  correctly; a pre-existing sitewide narrow-viewport overflow characteristic was confirmed present on
  the untouched `papagayo.html` too, not caused by this change).
- `BIJAGUA-SLOTH-001` and `EXP-001-RINCON-COMMERCIAL-CLARITY` files reconfirmed byte-identical to
  baseline (0-diff) — no observation clock reset for either.
- **Technical debt logged, not fixed**: `MONTEVERDE_GUANACASTE_GEOGRAPHIC_ASSOCIATION` (Monteverde is
  administratively Puntarenas/Alajuela, not Guanacaste — flagged for a future separate accuracy review).
  The Tamarindo↔Coco/Hermosa cross-link gap (from Phase 2 research) also remains unimplemented.
- External cost: $0.00 (all research/DataForSEO spend for this opportunity happened in earlier phases;
  this implementation phase used only already-owned evidence).
- **Observation ID**: `GUANACASTE-WHERE-TO-STAY-001`. Checkpoints: Day 7 (~2026-10-01), Day 14
  (~2026-10-08), Day 28 (~2026-10-22). No ranking/traffic improvement promised — observation only. Full
  detail: `seo-intelligence/reports/guanacaste-where-to-stay-001-deployment-record.md`,
  `seo-intelligence/data/processed/guanacaste-where-to-stay-001-observation-record.json`.

## SITEWIDE-FAVICON-FIX-001 = LIVE (deployed 2026-09-24)

**Technical/infrastructure fix, not a content experiment — no observation window needed.** Fixed
Google Search showing a generic globe instead of a favicon: the site only served SVG/WebP favicons,
neither supported by Google Search (confirmed via Google's own docs). Added a real PNG
(`images/favicon-wildpapagayo.png`, 512x512, same existing brand mark) as the primary `<link
rel="icon">` across the entire site, kept SVG as a secondary tag, removed a broken duplicate tag that
existed on `index.html`/`travel-insurance.html`. Fixed at the template/generator source level
(`templates/tour.html`, `destination.html`, `hotel.html`, `experience-guide.html`, `category.html`,
`month.html`, `profile.html`, `landing-page.html`, `blog-generator.ps1`) plus 20 hand-authored root
pages with no shared generator. 161 total files changed across 2 deploys (`382322a5`, then a 1-file
homepage follow-up `f5fa5748` after the first deploy was found to predate an earlier same-session
homepage fix). Verified favicon-only via a strip-and-compare check on every changed file (0 files had
any non-favicon difference). `llms.txt`, canonical/meta/schema, pricing, both active experiments
(BIJAGUA-SLOTH-001, EXP-001), and all protected RIU pages confirmed untouched/semantically identical.
PNG confirmed live at `https://wildpapagayo.com/images/favicon-wildpapagayo.png` (HTTP 200,
image/png). External cost: $0.00. Full detail:
`seo-intelligence/reports/favicon-fix-sitewide-technical-record.md`. **Google Search itself can take
days to weeks to show the updated favicon — this is an observation item, not yet independently
confirmed in live Search results.**

## EXP-001-RINCON-COMMERCIAL-CLARITY = PARTIALLY LIVE (FAQ only, deployed 2026-09-24, 08:21 CST / 14:21 UTC)

> **Content change during observation (2026-09-26, prepared locally, not deployed):** `tours/hikingrinconnationalpark`
> gets the standard 72-hour booking/cancellation policy (reservation-policy accordion, "Can I cancel my
> reservation?" FAQ + its JSON-LD, trust strip, footer label) under `BOOKING-POLICY-72H-001`. Owner approved
> correcting outdated policy text on observed pages. If deployed, treat that date as a content-change marker.

**Only 1 of the 2 approved change components was implemented. The other was correctly NOT implemented
after a real architectural conflict was discovered — read this before touching this page again.**

- **Deployed**: `/tours/hikingrinconnationalpark` gained exactly one new FAQ pair ("How much does this
  tour cost?", answer using only the already owner-confirmed $100/$250/$270 figures and their existing
  tier descriptions — no new numbers, no pricing schema change). Deployment `8150d77e`, verified on
  both the deployment URL and the custom domain (title/H1/canonical unchanged, FAQ visible=schema=12,
  0 mismatches). Real cost: $0.00.
- **NOT deployed, and should not be attempted as a single-page change**: repositioning the pricing
  block "earlier on the page." Direct inspection of `templates/tour.html` + `style.css` this task found
  the pricing/summary card's document position is controlled by a **single shared template** used by
  all 33 tour pages (`__PRICING_GUIDE_ONLY__`/`__PRICING_OPTIONS__` placeholders), and its actual
  *visual* position is controlled by shared, sitewide CSS (`.tour-summary-card { order: 1; }` plus a
  `max-width:819px` mobile reorder and a `min-width:820px` two-column desktop layout) — **not by
  per-tour JSON data**. Any change to make Rincón's pricing render earlier would require editing the
  shared template or shared CSS, which would also move pricing on every other tour page, including
  `tours/slothadventure.html` (the currently-LIVE, protected `BIJAGUA-SLOTH-001` experiment) — an
  explicit STOP condition. **This also means the original diagnostic premise (pricing "buried very
  late in the page") was based only on raw HTML document order and was likely wrong about actual
  rendered prominence** — the CSS `order` rule means the price card already renders first-visible on
  mobile and as an always-present right-hand sidebar on desktop for every tour page site-wide,
  including this one, both before and after this task. If a real page-specific pricing-prominence
  problem is still believed to exist, it needs to be re-diagnosed with actual rendered/visual
  evidence (e.g. a screenshot or computed-layout check), not HTML source order, before any further
  template or CSS change is proposed.
- Full detail: `seo-intelligence/reports/exp-001-rincon-owner-confirmation-closure.md`,
  `seo-intelligence/data/processed/exp-001-rincon-final-design.json`.
- **CORRECTION (2026-09-24, same day, rendered-layout verification task)**: the "pricing buried very
  late" diagnosis above is **superseded**, not deleted — preserved for chronology. Real headless-Chrome
  screenshots of the live production page at 390px/430px/1280px found the diagnosis was a
  `SOURCE_ORDER_FALSE_POSITIVE`: a previously-missed template element (`__PRICE_TEASER__`,
  `tour-generator.ps1` lines 629-642) already shows a "From $X" price + CTA well before the FAQ, on
  every tested viewport, both in raw source order and rendered order. **Corrected verdict:
  `NO_VISUAL_PROMINENCE_PROBLEM`. No pricing-reposition change is needed or planned.** `EXP-001` is now
  closed as exactly the one-FAQ intervention already deployed — nothing more. Full detail:
  `seo-intelligence/reports/exp-001-rincon-rendered-layout-verification.md`. **A permanent methodology
  rule was added to `CLAUDE.md`** ("Rendered-layout verification rule") requiring real rendered/visual
  evidence — not raw HTML source order alone — before concluding a prominence/visual-order/CTA-visibility
  problem exists on any page.
- `BIJAGUA-SLOTH-001` reconfirmed byte-identical live (beyond the same benign Cloudflare
  email-obfuscation edge injections) — its observation window (Day 7 ~2026-10-01, Day 14 ~2026-10-08,
  Day 28 ~2026-10-22) is untouched and unaffected.
- `../wild-papagayo-deploy-current-baseline` refreshed to match, still 529 files.
- **Observation checkpoints for the FAQ-only change**: Day 14 (~2026-10-08), Day 28 (~2026-10-22) — no
  Day 7 checkpoint, deliberately, given this query's very low real GSC impression volume (~24 over 69
  days). Do not add another Rincón pricing/FAQ change or attempt the pricing-reposition idea again
  during this window without first re-diagnosing actual rendered prominence.

## BIJAGUA-SLOTH-001 = LIVE (deployed 2026-09-24, 08:03 CST / 14:03 UTC)

> **Content change during observation (2026-09-26, prepared locally, not deployed):** `tours/slothadventure`
> gets the standard 72-hour booking/cancellation policy (reservation-policy accordion, trust strip, footer
> label; this tour has no cancellation FAQ) under `BOOKING-POLICY-72H-001`. `destinations/bijagua` only gets
> the footer label. If deployed, treat that date as a content-change marker.

**Narrow, controlled experiment on an existing page — not a new page.** `/tours/slothadventure` and
`/destinations/bijagua` both updated. Deployment `869e1459`, verified on both the deployment URL
(`https://869e1459.wild-papagayo.pages.dev`) and the custom domain. No IndexNow, no indexing request.

- Preceded by the DFS-MONITOR-V1 baseline + Phase 2 + Phase 3 + Phase 3B research chain (all in
  `seo-intelligence/reports/dataforseo-monitoring-v1-*.md`, `phase3b-bijagua-decision-closure.md`,
  `bijagua-sloth-tour-opportunity-analysis.md`), which found real search demand (20/mo, HIGH
  competition) for "bijagua sloth tour" and diagnosed the gap as **presentation, not missing
  information or a missing product** — Wild Papagayo's existing `slothadventure` tour already operates
  in Bijagua (owner-confirmed operational fact, 2026-09-24) but mentioned "Bijagua" only once, in a
  single mid-page H3 heading.
- Owner-confirmed fact used: "The Sloth Adventure sold by Wild Papagayo genuinely takes place in
  Bijagua." Scoped narrowly — no claim was added about exact address, distance/drive time from Bijagua
  town, guaranteed sightings, or the specific reserve/trail; none of those are confirmed anywhere in
  project evidence.
- Exactly 3 approved changes, all reusing existing owner-confirmed facts, no new information invented:
  (1) `page_content.hero_subtitle_html` in `knowledge/tours/slothadventure.json` now reads "...walk the
  **Bijagua** rainforest..." (was "...walk the rainforest..."); (2) one new FAQ pair appended to
  `page_content.faq` in the same file ("Does this tour take place in Bijagua?"); (3)
  `knowledge/destinations/bijagua.json`'s `featured_tours` array gained `"slothadventure"`, producing
  one new experience card linking `destinations/bijagua` → `tours/slothadventure`.
- Regenerated via the real pipeline (`tour-generator.ps1`, `destination-generator.ps1`), not
  hand-patched. Title, H1, meta description, canonical, and pricing on `tours/slothadventure` are all
  **unchanged** — deliberately out of scope for this experiment (Phase 3B's diagnostic mention of those
  fields did not itself authorize changing them). FAQ visible content and FAQPage schema confirmed
  synchronized (8 = 8, 0 mismatches, re-verified live).
- Surgical deploy: built from `../wild-papagayo-deploy-current-baseline` (verified byte-equal to live
  production before this deploy, confirmed via direct fetch), overlaid with only the 2 regenerated
  files, gated with `diff -rq` against the baseline (confirmed exactly 2 files differ, file count
  unchanged at 529) before deploying. `../wild-papagayo-deploy-current-baseline` refreshed afterward to
  match, still 529 files.
- Regenerating `tour-generator.ps1`/`destination-generator.ps1` also rewrote ~32 other tour pages and
  10 other destination pages already sitting in the pre-existing untracked/modified working-tree state
  (the long-documented drift — unrelated `knowledge/tours/*.json` and `knowledge/destinations/*.json`
  files were not touched this task) — confirmed via direct diff against live production that none of
  those other regenerated files differ from what's already live (spot-checked `destinations/rio-celeste`
  and `hotels/hotel-riu-guanacaste`; only the standard Cloudflare email-obfuscation/edge-script
  injections appear, not content changes) — none of those other files were part of this deploy's
  overlay, only the 2 intended files were uploaded.
- Protected experiments reconfirmed unaffected (spot-checked `hotels/hotel-riu-guanacaste`): only the
  same benign Cloudflare edge injections, not content changes.
- External cost: $0.00 (no DataForSEO or other paid API call this task).
- **Observation checkpoints: Day 7 (~2026-10-01), Day 14 (~2026-10-08), Day 28 (~2026-10-22).** Do not
  add a second Bijagua-targeting change, a new Bijagua article/landing, or further edits to either page
  during this window unless a real production defect is found — the point is to observe this one
  narrow intervention in isolation. The still-open `EXP-001` (Rincón de la Vieja pricing-prominence
  experiment, blocked on an owner confirmation of current price accuracy) was **not** started this task.

## RIU-EXCURSIONS-BEYOND-RESORT-001 = LIVE (deployed 2026-09-23, 12:58 CST / 18:58 UTC)

**This is an UPDATE to two existing articles, not a new-content experiment; no new URL.** Deployment
`529342f8`, verified on both the deployment URL and the custom domain. No IndexNow, no indexing request.

- Preceded by `seo-intelligence/reports/riu-guanacaste-palace-excursions-content-ownership-analysis.md`
  (found both "Best Tours From RIU X" articles already live and already the correct owners — decision
  UPDATE_EXISTING, DataForSEO $0.00) and an owner-confirmation round resolving the nearby-town-transportation
  and off-resort-nightlife-transportation questions the research flagged as blocking.
- Owner-confirmed facts used: Wild Papagayo can arrange private round-trip transportation (not a tour/
  excursion) from RIU Guanacaste or RIU Palace to Playas del Coco or Tamarindo, on request, including for
  evening/off-resort use. No surf-lesson, surf-booking, nightlife-tour, bar-crawl, nightclub-reservation, or
  bar/club-recommendation claim was made anywhere.
- Affected URLs (both unchanged, no new URL):
  `/blog/best-tours-from-riu-guanacaste-local-recommendations` (id 14) — new closing section "Beyond These
  Tours: Nearby Towns" + 2 new FAQs (surf, nightlife); FAQ count 8→10.
  `/blog/best-tours-from-riu-palace-costa-rica` (id 43) — new closing section "What About Leaving the Resort
  Without a Tour?" + 2 new FAQs (surf, nightlife), deliberately worded differently from the Guanacaste version
  (not a mechanical duplicate); FAQ count 7→9.
- Shipped exactly 2 files (`blog-data.json` is the only source-of-truth file touched): the two regenerated
  article HTML files. Sitemap (175), RSS (56), and `llms.txt` all confirmed byte-identical to baseline — no
  new URL was introduced, so none needed updating.
- FAQPage schema confirmed exactly matching visible FAQ text for both articles (10=10, 9=9), 0 mismatches.
  Schema types exactly TravelAgency, BlogPosting, BreadcrumbList, FAQPage — unchanged. Title, H1, canonical,
  hero, and primary CTA all confirmed unchanged on both articles.
- Both new sections link to `../transport` (already an existing internal-link target in both articles) — no
  new internal-link entries forced, no other article modified.
- **SEPARATE_VISUAL_DEBT (flagged, not fixed):** both RIU hotel pages
  (`knowledge/hotels/hotel-riu-guanacaste.json`, `knowledge/hotels/hotel-riu-palace-costa-rica-...json`) carry
  `"hero_image_status": "google_places_photo"`, a third-party-sourced hero image conflicting with the
  standing no-third-party-photos rule. Neither hotel page was touched this task; this remains open for a
  separate future task.
- Protected experiments reconfirmed byte-identical live vs. package (beyond the same known benign Cloudflare
  injections): both RIU airport-transfer landings, both RIU hotel pages, `BLOG-SJO-LA-FORTUNA-ARRIVAL-001`,
  `BLOG-COSTA-RICA-WITHOUT-CAR-001`. No observation clock reset.
- External cost: $0.00.

## BLOG-SJO-LA-FORTUNA-ARRIVAL-001 = LIVE (deployed 2026-09-23, 12:37 CST / 18:37 UTC)

`/blog/sjo-to-la-fortuna-continue-or-overnight` is live (Cloudflare deployment `8bd296bd`,
https://8bd296bd.wild-papagayo.pages.dev), deployed and verified on both the deployment URL and the custom
domain. No IndexNow, no indexing request — discoverable via sitemap/RSS/internal links/llms.txt only.

- Full pipeline: content-ownership research (`seo-intelligence/reports/sjo-la-fortuna-arrival-day-content-
  ownership-analysis.md`, DEFER → revised to FUTURE_PARENT after owner confirmation) → build spec
  (`seo-intelligence/reports/sjo-la-fortuna-arrival-day-parent-build-spec.md`) → article implementation
  (blocked on `HERO_IMAGE_REQUIRED` — 4 candidate unused images rejected: one likely AI-generated, one
  third-party-branded, one non-Costa-Rica stock photo, one with no thematic fit) → owner supplied and approved
  a real photo → hero integrated (license plate pixelated, conventional non-generative edit only) → deployed.
  External cost: $0.00 throughout (no DataForSEO called at any stage).
- Owner-confirmed operational facts used: Wild Papagayo can provide private SJO→La Fortuna/Arenal
  transportation on request; the airport→La Fortuna transfer does not continue for night arrivals (same
  policy as the live LIR route); for arrivals after 4:00 p.m. Wild Papagayo generally recommends an SJO-area
  overnight stay (explicitly a planning recommendation, never phrased as a safety or legal claim); rental-car
  travelers get a more conservative recommendation than private-driver travelers, though the night restriction
  applies to both.
- Shipped exactly 5 files: new article `blog/sjo-to-la-fortuna-continue-or-overnight.html` (id 59, 56th blog
  article, category Transportation & Transfers); new hero image
  `images/sjo-la-fortuna-private-transportation.webp` (1600x1200, license-plate pixelation only, from a real
  owner photo); `sitemap.xml` (+1 URL, 175 total); `rss.xml` (+1 item placed first, 56 total — a same-date
  tiebreak with the protected `costa-rica-without-a-car-guide` entry was caught before deploy: a full
  `-RefreshRss` run silently reordered several older same-date items relative to the live baseline, so that
  approach was rejected; the new article's `iso_date` was instead bumped to a later same-day timestamp and the
  new item was manually prepended onto the real baseline RSS, leaving all 55 prior items byte-identical,
  confirmed live); `llms.txt` (+1 line, Travel Guides section, after the Papagayo arrival-day entry, before
  Airport Transfers).
- No H1 field exists separately from `title` in this site's template (confirmed via `blog-generator.ps1`) —
  the approved build spec's distinct H1 phrasing could not be applied; H1 = title, consistent with every other
  article on the site. Flagged as a template constraint, not a content deviation.
- `../wild-papagayo-deploy-current-baseline` refreshed to 529 files, confirmed equal to live (protected pages —
  `costa-rica-without-a-car-guide`, `playa-hermosa-guanacaste-with-kids`, `ditching-the-crowds`, the
  LIR→La Fortuna transfer landing — show only the standard Cloudflare email-obfuscation/analytics-beacon edge
  injections, not content changes).
- `recommended_tour_ids` intentionally omitted (logistics-only article, no natural tour tie-in). 7 FAQs,
  FAQPage schema confirmed exactly matching visible FAQ text (0 mismatches, re-verified live). Schema types
  exactly TravelAgency, BlogPosting, BreadcrumbList, FAQPage. 7 outbound internal links confirmed live/200.
- Deferred inbound link: the Next-nav link from `costa-rica-without-a-car-guide` (protected, mid-observation)
  was deliberately not added. Two other inbound candidates (airport-choice article, La Fortuna duration
  article) also not touched this deploy.
- **Observation checkpoints:** Day 7 (~2026-09-30), Day 14 (~2026-10-07), Day 28 (~2026-10-21). No content
  changes during this window unless a real production defect is found. No other experiment's observation clock
  was reset.

## BLOG-DITCHING-CROWDS-SEMANA-SANTA-001 = LIVE_VERIFIED (deployed 2026-09-23, 11:23 CST / 17:23 UTC)

**This is an UPDATE to an existing article, not a new-content experiment.** `/blog/ditching-the-crowds`
gained a new "What About Semana Santa (Easter Week)?" section and 2 new FAQ pairs. Live (Cloudflare
deployment `760c9ca1`, https://760c9ca1.wild-papagayo.pages.dev), verified on both the deployment URL
and the custom domain. No IndexNow, no indexing request.

- Preceded by `seo-intelligence/reports/guanacaste-semana-santa-opportunity-analysis.md`
  (ADD_SECTION recommendation, DataForSEO cost $0.00 — the content-ownership audit alone resolved the
  architecture question) and the GSC evidence-workflow fix (see `seo-intelligence/data/gsc/`).
  Owner-confirmed operational facts used: beaches/waterfalls draw particularly large Semana Santa
  crowds; Wild Papagayo may recommend shifting an excursion to another day or an alternative tour;
  some attractions may be closed on particular dates so operating status gets checked; no blanket
  avoidance framing. Alcohol-sale restrictions deliberately excluded per owner instruction. External
  facts (Semana Santa 2026 dates, mid-week outbound surge pattern) are illustrative/dated, not
  hardcoded as permanent.
- Shipped exactly 1 file: `blog/ditching-the-crowds.html` (source: `blog-data.json` id 1,
  `content_block_2` +1 section, `content_block_faq` +2 pairs). No new URL, no sitemap/RSS/llms.txt
  change (article count and URL unchanged — 174 sitemap URLs, 55 RSS items, both confirmed unchanged
  live). Title, H1, canonical (`https://wildpapagayo.com/blog/ditching-the-crowds`) and hero
  (`images/costa-rica-without-the-crowds.webp`) all confirmed unchanged live. FAQPage schema (5 items)
  confirmed exactly matching 5 visible FAQs (3 original + 2 new), 0 mismatches. Schema types exactly
  TravelAgency, BlogPosting, BreadcrumbList, FAQPage. No `.html` internal links introduced.
- `../wild-papagayo-deploy-current-baseline` refreshed, still 527 files (update-only, no file count
  change), confirmed equal to live (protected pages show only the standard Cloudflare
  email-obfuscation/analytics-beacon edge injections, not content changes).
- Protected experiments reconfirmed byte-identical live vs. pre-deploy baseline (beyond the same
  benign Cloudflare injections): `BLOG-COSTA-RICA-WITHOUT-CAR-001` article, `BLOG-PLAYA-HERMOSA-
  FAMILY-001` article, both RIU hotel pages, and the LIR→La Fortuna transfer landing. No observation
  clocks reset.
- External cost this task: $0.00.

## BLOG-COSTA-RICA-WITHOUT-CAR-001 = LIVE_VERIFIED (deployed 2026-09-22, 19:37 CST / 2026-09-23 01:37 UTC)

`/blog/costa-rica-without-a-car-guide` is live (Cloudflare deployment 3dac2c33,
https://3dac2c33.wild-papagayo.pages.dev), deployed and verified 2026-09-22/23. No IndexNow, no indexing request —
page is discoverable via sitemap/RSS/internal links only, normal observation period.

- Full pipeline this experiment: SEO cluster research (DataForSEO Standard Queue task, $0.06 — "costa rica wildlife
  trip" 720/mo LOW competition was the standout signal; Fodor's owns the general "7-day without a rental car" head
  term; 6 of 12 keywords returned real volumes, the rest correctly classified INSUFFICIENT_DATA, not zero) → build
  specification (scope deliberately narrowed to an LIR-corridor guide, not a national no-car page; owner resolved
  two blockers — private inter-destination transport routes confirmed, shared-shuttle third-party-referral role
  confirmed) → article implementation (1,809 words, 7 FAQs, 10/10 AI static validation) → hero integration (owner
  photo verified against two rejected alternates by direct visual comparison; conventional non-generative
  pixelation applied to the front license plate; no AI-generated image used) → live deployment. Total external
  cost for the whole opportunity: $0.06.
- Shipped exactly 5 public files: new article `blog/costa-rica-without-a-car-guide.html` (id 58, 55th blog
  article, category Trip Planning); new hero image `images/costa-rica-without-car.webp` (1600x1200, license-plate
  pixelation only, no crop/no resize/no generative edit, from the owner's real photo
  `WhatsApp Image 2026-09-22 at 7.17.19 PM.jpeg`); `blog/playa-hermosa-guanacaste-with-kids.html` (+1 Next-nav
  link only); `sitemap.xml` (+1 URL, 174 total); `rss.xml` (+1 item placed first, 55 total, previous 54 items
  confirmed byte-identical and in original order). `llms.txt` deliberately NOT modified
  (`LLMS_TXT_ACTION = NO_CHANGE`), confirmed byte-identical live vs. package vs. baseline.
- `../wild-papagayo-deploy-current-baseline` refreshed to 527 files, confirmed equal to live (protected transfer
  pages and hotel pages show only the standard Cloudflare email-obfuscation/analytics-beacon edge injections plus
  CRLF normalization, not content changes).
- Scope: content explicitly limited to the Liberia (LIR) / Guanacaste / La Fortuna corridor — no national
  Costa-Rica-without-a-car coverage claim made anywhere in the article. Four transport modes compared (private
  transfer, shared shuttle, rental car, public bus) with transparent solo-traveler economics; shared shuttle
  explicitly identified as third-party, not a Wild Papagayo service; Wild Papagayo private transportation
  correctly distinguished from tours; no fixed/generic pricing quoted; no wildlife-sighting guarantee made
  ("no guide or tour can guarantee sightings on any given day"); Bijagua kept optional, no product forced onto it.
- 6 internal links confirmed live/200: `liberia-airport-transfer-guide`, `how-many-days-la-fortuna`,
  `la-fortuna-without-a-rental-car-an-honest-trip-recap`,
  `liberia-or-san-jos-airport-which-is-better-for-guanacaste`, `costa-rica-with-a-baby-without-rental-car`,
  `playa-hermosa-guanacaste-with-kids`. FAQPage schema (7 items) confirmed exactly matching 7 visible FAQs, 0
  mismatches. Schema types exactly TravelAgency, BlogPosting, BreadcrumbList, FAQPage — no unexpected types, no
  duplicate organization entity. `recommended_tour_ids` intentionally omitted (logistics-only article, no natural
  tour tie-in).
- Deferred child not created this session: `7_10_DAY_WILDLIFE_NO_CAR_ITINERARY` (itinerary-format follow-up,
  explicitly out of scope for this pillar article).
- Observation clock started 2026-09-22/23. Suggested checkpoints: Day 7 (2026-09-29/30), Day 14 (2026-10-06/07),
  Day 28 (2026-10-20/21). No cosmetic SEO edits during this window unless a genuine defect is found.

## BLOG-PLAYA-HERMOSA-FAMILY-001 = LIVE_VERIFIED (deployed 2026-09-22, 18:00 CST / 2026-09-23 00:00 UTC)

`/blog/playa-hermosa-guanacaste-with-kids` is live (Cloudflare deployment 8f3edad9,
https://8f3edad9.wild-papagayo.pages.dev), deployed and verified 2026-09-22/23. No IndexNow, no indexing request —
page is discoverable via sitemap/RSS/internal links only, normal observation period.

- Full pipeline this experiment: SEO opportunity research (DataForSEO Standard Queue task, $0.06, all 13 keywords
  returned INSUFFICIENT_DATA/null, not zero — decision made on SERP/architecture evidence, not volume) → build
  specification → article implementation → hero provenance correction (an AI-generated PNG was caught and
  rejected before integration; the real owner camera photo, `DSC01450.JPG`, Sony DSC-W530, EXIF-dated 2012-05-28,
  was used instead) → live deployment. Total external cost for the whole opportunity: $0.06.
- Shipped exactly 5 public files: new article `blog/playa-hermosa-guanacaste-with-kids.html` (id 57, 54th blog
  article, category Trip Planning); new hero image `images/playa-hermosa-guanacaste-family.webp` (1600x1200,
  proportional resize + WebP conversion only, no crop/generative edit, from the owner's real photo);
  `blog/what-to-do-on-your-first-day-in-papagayo.html` (+1 Next-nav link only); `sitemap.xml` (+1 URL, 173
  total); `rss.xml` (+1 item placed first, 54 total, previous 53 items confirmed byte-identical and in original
  order). `llms.txt` deliberately NOT modified (`LLMS_TXT_ACTION = NO_CHANGE`), confirmed byte-identical live vs.
  package vs. baseline.
- `../wild-papagayo-deploy-current-baseline` refreshed to 525 files, confirmed equal to live (protected transfer
  pages show only the standard Cloudflare email-obfuscation/year-script edge injections, not content changes).
- Geography: article explicitly disambiguates Playa Hermosa, Guanacaste (calm bay, family-oriented, Gulf of
  Papagayo) from the surf beach of the same name near Jacó, Puntarenas, near the top of the article.
- Operational facts, all owner-confirmed for this article specifically (not generalized to other operators):
  Palo Verde River Boat minimum age = 2 years; Congo Trail minimum age = 4 years, with horseback (5+) and ATV
  (6+) component restrictions preserved separately per current tour source. Approximate Playa Hermosa planning
  times published: Congo Trail ~30m, Las Pumas ~1h10m, Palo Verde ~1h15m, Rincón ~1h15m, Río Celeste
  ~1h45m — all labeled approximate, one caveat sentence stated once. Bijagua (~1h35m owner estimate)
  deliberately excluded — no current Wild Papagayo product could be reliably mapped to it.
- `recommended_tour_ids` intentionally omitted — 0 Recommended Tours cards, exactly 3 Keep Reading cards. 8
  FAQs, FAQPage schema confirmed exactly matching visible FAQ text (0 mismatches, re-verified live). 6 direct
  tour-page links (Palo Verde River Boat, Rincón de la Vieja Hiking, Las Pumas & Waterfall, Tubing at
  Río Celeste, Celeste River Hike & Tenorio, Congo Trail) all confirmed live/200.
- **New source-of-truth cleanup debt recorded (not repaired this session):**
  `PALO_VERDE_MINIMUM_AGE_CONFLICT` (`knowledge/tours/paloverderiverboattour.json` says 8, owner-confirmed
  operational fact is 2 — appears to resolve the long-standing "River Boat minimum age" unresolved note);
  `CONGO_TRAIL_MINIMUM_AGE_CONFLICT` (flat field says 0, owner-confirmed operational fact is 4, with 5+/6+
  component restrictions); `BIJAGUA_PRODUCT_MAPPING` (unresolved, excluded from article);
  `PLAYA_HERMOSA_DESTINATION_FAM1_IMAGE` — `knowledge/destinations/playa-hermosa.json`'s own `hero_image`
  (`fam.1.webp`) appears to be stock photography (posed family, coordinated outfits, generic tropical beach not
  matching Playa Hermosa's documented gray-sand/calm-bay appearance) currently live on the destination page;
  flagged for separate attention, not touched.
- No tour/hotel/transfer/destination pages regenerated (destination page explicitly out of scope this session
  despite the fam.1.webp finding above). Global deterministic RSS correction still NOT deployed. Unrelated
  pre-existing working-tree drift remains untouched and unstaged.
- **Observation checkpoints:** Day 7 (~2026-09-29), Day 14 (~2026-10-06), Day 28 (~2026-10-20). Measure:
  indexation, impressions/clicks/average position for the Group A/C query sets from the opportunity research
  (DataForSEO volume was INSUFFICIENT_DATA, so Search Console's own query data is the real signal here), any
  Playa Hermosa disambiguation-pattern query discovery, AI referral/citation observations where measurable,
  internal click-through to the 6 linked tour pages. No observation clocks for other active experiments were
  reset.

## BLOG-ARRIVAL-DAY-PAPAGAYO-001 = LIVE_VERIFIED (deployed 2026-09-22)

`/blog/what-to-do-on-your-first-day-in-papagayo` is live (Cloudflare deployment 1b35a0b0,
https://1b35a0b0.wild-papagayo.pages.dev), deployed and verified 2026-09-22. No IndexNow, no indexing request.

- Shipped exactly 6 public files: new article `blog/what-to-do-on-your-first-day-in-papagayo.html` (id 56, 53rd
  blog article, category Trip Planning); new hero image `images/arrival-day-private-van.webp`;
  `blog/dry-season-in-guanacaste-what-to-expect.html` (+1 Next-nav link only, everything else byte-identical);
  `sitemap.xml` (+1 URL, 172 total); `rss.xml` (+1 item placed first, 53 total, previous 52 items confirmed
  byte-identical and in original relative order — global deterministic RSS correction still NOT deployed this
  session); `llms.txt` (+1 line, inserted directly after the Dry Season line).
- `../wild-papagayo-deploy-current-baseline` refreshed to 523 files with exactly those 6 files, confirmed equal to
  live (the two HTML files show a byte-level diff from Cloudflare's own edge injections — email-obfuscation
  rewriting and the Web Analytics beacon script — not a content difference).
- Hero: `images/arrival-day-private-van.webp` — a real user-provided photo (silver Mercedes Sprinter passenger
  van, sliding door open, tropical landscaped setting, no people, no hotel signage, front license plate visible
  but confirmed unreadable at maximum zoom). Native resolution is 669×446, smaller than this site's other heroes
  (typically 1600px+ wide); the user explicitly accepted this as-is rather than sourcing a higher-resolution
  replacement. Passed all crop tests (desktop/mobile/1.91:1/2:1). Confirmed unused prior to assignment.
- This is the arrival-day mirror of the Departure-Day article, mirrored deliberately in structure but NOT in
  operational claims: the article explicitly states that airport→tour→hotel is **not** a standard workflow
  (every tour begins with hotel pickup, confirmed via source review of 8+ tour products), and explicitly avoids
  creating a false symmetry with Departure-Day's separate, already-sourced custom tour→airport option. This was
  the article's single biggest operational risk and was verified clean at both the draft and final-lock stages.
- Claims discipline: 30–45 min LIR→Papagayo figure scoped strictly to drive time, never combined with unsourced
  airport-processing time into a single landing-to-hotel estimate; no invented hotel check-in time (none exists
  in schema); no luggage-storage guarantee; grocery-stop language scoped exactly to "on request," not broadened
  to restaurant/lunch/sightseeing stops; family/travel-fatigue framing kept general and non-medical; no La Fortuna
  or other wrong-geography content introduced (one false-positive "La Fortuna" string match during live
  verification traced to an unrelated sitewide Keep-Reading card, not the article's own authored text).
- `recommended_tour_ids` intentionally omitted (not set to `[]`) — 0 Recommended Tours cards, exactly 3 Keep
  Reading cards (confirmed live). No `.html` internal links. 7 FAQs, FAQPage schema confirmed exactly matching
  visible FAQ text (0 mismatches, re-verified live).
- No tour/hotel/transfer/destination pages regenerated. Logistics/seasonal neighbor cluster
  (`liberia-airport-transfer-guide`, `how-to-get-around-from-papagayo`, `best-half-day-tours-from-papagayo`,
  `can-you-do-a-tour-on-your-departure-day-from-papagayo`, `things-to-do-in-papagayo-costa-rica`, Dry Season except
  its approved Next-link) confirmed unchanged. Global deterministic RSS correction still NOT deployed. Unrelated
  pre-existing working-tree drift remains untouched and unstaged. Four Seasons `best_season` outlier and Palo
  Verde ops-notes gaps remain unresolved, unchanged from prior sessions.

## BLOG-DRY-SEASON-IN-GUANACASTE-001 = LIVE_VERIFIED (deployed 2026-09-22)

`/blog/dry-season-in-guanacaste-what-to-expect` is live (Cloudflare deployment 9ea83715,
https://9ea83715.wild-papagayo.pages.dev), deployed and verified 2026-09-22. No IndexNow, no indexing request.

- Shipped exactly 6 public files: new article `blog/dry-season-in-guanacaste-what-to-expect.html` (id 55, 52nd
  blog article, category Weather & Seasons); new hero image `images/dry-season-guanacaste-beach.webp`;
  `blog/can-you-do-a-tour-on-your-departure-day-from-papagayo.html` (+1 Next-nav link only, everything else
  byte-identical); `sitemap.xml` (+1 URL, 171 total); `rss.xml` (+1 item placed first, 52 total, previous 51
  items confirmed byte-identical and in original relative order — global deterministic RSS correction still NOT
  deployed this session); `llms.txt` (+1 line, inserted directly after the Departure-Day line).
- `../wild-papagayo-deploy-current-baseline` refreshed to 521 files with exactly those 6 files, confirmed equal to
  live (the two HTML files show a byte-level diff from Cloudflare's own edge injections — email-obfuscation
  rewriting and the Web Analytics beacon script — not a content difference). Wrangler uploaded only 5 new files
  (not 6) because the hero is byte-identical to an already-uploaded asset, so Cloudflare's content-addressed
  storage deduplicated it — expected, not an error.
- Hero: `images/dry-season-guanacaste-beach.webp` — an explicit **content reuse** of the existing
  `guanacaste-hero.webp` (already the hero of `which-day-trip-from-papagayo-fits-you`) saved under a new filename.
  This reuse was flagged directly to the user as conflicting with both the task's own "do not substitute
  guanacaste-hero.webp" instruction and this session's standing no-hero-reuse practice; the user explicitly
  confirmed "use it anyway, reuse approved" before it was assigned. Byte-identical copy (SHA-256 verified, no
  re-encoding), crop-tested clean at desktop/mobile/1.91:1/2:1.
- Dry-season definition: December–April, sourced from `knowledge/seasons.json` and `papagayo.json`. Peak/busiest
  booking-pressure window kept distinct at December–March (source: `guanacaste.json`), with April explicitly not
  inheriting the same booking-pressure framing. One editorial fix applied during final review: "December through
  March is the core dry season and the busiest period for booking" was rewritten to "December through March is
  the busiest part of the travel season within the dry-season window" — the original risked implying a sourced
  meteorological (not just booking) distinction between Dec–Mar and April.
- Claims discipline: no guaranteed-sunshine language, no rainfall totals, no temperature numbers, no wind content
  (all "wind" substring hits were "window," confirmed false positives), no pricing claims, no fixed booking
  lead-time numbers. Palo Verde wildlife-visibility claim explicitly scoped to Palo Verde only, not generalized.
  Río Celeste inland-rain nuance preserved (dry coastal season ≠ guaranteed inland dryness). Rincón road nuance
  kept to source-safe inverse inference only. Ostional deliberately excluded (its sourced arribada window is
  August–November, the opposite season — including it would have implied a false Dec–Apr connection).
- **Known separate data-cleanup note (not fixed here):** `knowledge/master/hotels/four-seasons-papagayo.json`
  → `planning.best_season: "December to August"` conflicts with both `seasons.json` and `papagayo.json`'s
  December–April definition. Confirmed the article does not incorporate or inherit this outlier value.
- `recommended_tour_ids` intentionally omitted (not set to `[]`) — 0 Recommended Tours cards, exactly 3 Keep
  Reading cards (confirmed live). No `.html` internal links. 7 FAQs, FAQPage schema confirmed exactly matching
  visible FAQ text (0 mismatches, re-verified live after the editorial fix).
- No tour/hotel/transfer/destination pages regenerated. Seasonal-neighbor cluster (`costa-rica-in-september-
  will-rain-ruin-your-tours`, `green-season-packing-list-guanacaste-arenal`, `things-to-do-in-papagayo-costa-rica`,
  `which-day-trip-from-papagayo-fits-you`, `palo-verde-vs-rincon-de-la-vieja-from-papagayo`) confirmed unchanged.
  Global deterministic RSS correction still NOT deployed. Unrelated pre-existing working-tree drift (hundreds of
  modified/deleted images, `hotel-generator.ps1`, several hotel pages, `tours/fincaaventura.html` deletion)
  remains untouched and unstaged, consistent with prior tasks this session.

## BLOG-CAN-YOU-DO-A-TOUR-ON-DEPARTURE-DAY-001 = LIVE_VERIFIED (deployed 2026-09-22)

`/blog/can-you-do-a-tour-on-your-departure-day-from-papagayo` is live (Cloudflare deployment ec0ea50e,
https://ec0ea50e.wild-papagayo.pages.dev), deployed and verified 2026-09-22. No IndexNow, no indexing request.

- Shipped exactly 6 public files: new article `blog/can-you-do-a-tour-on-your-departure-day-from-papagayo.html`
  (id 54, 51st blog article, category Trip Planning); new hero image `images/departure-day-private-van.webp`;
  `blog/which-day-trip-from-papagayo-fits-you.html` (+1 Next-nav link only, Canyon vs Congo contextual link
  confirmed still intact, everything else byte-identical); `sitemap.xml` (+1 URL, 170 total); `rss.xml` (+1 item
  placed first, 51 total, previous 50 items confirmed byte-identical and in original relative order — global
  deterministic RSS correction still NOT deployed this session); `llms.txt` (+1 line, inserted directly after the
  Day-Trip Hub line).
- `../wild-papagayo-deploy-current-baseline` refreshed to 519 files with exactly those 6 files, confirmed equal to
  live (two HTML files show a byte-level diff from Cloudflare's own edge injections — email-obfuscation rewriting
  and the Web Analytics beacon script — not a content difference). `../wild-papagayo-deploy-blog-departure-day` was
  the deployed package (removed after verification).
- Hero: `images/departure-day-private-van.webp` — a real user-provided photo (white Toyota Hiace-style tourism van,
  visible "TURISMO" legal marking on the rear-left panel, parked at a tropical property). The property's location
  in Papagayo was explicitly confirmed by the user after an initial review flagged the porte-cochere architecture
  as potentially identifying a specific resort (an internal-source, non-third-party photo, so this is a geography
  confirmation, not a provenance exception to the standing no-third-party-photos rule). TURISMO is a generic
  Costa Rican legal tourism-vehicle marking (not a brand), confirmed to fade to illegible at mobile width (390px)
  and stay secondary (not dominant) at desktop/social sizes — approved as-is, no digital alteration. No legible
  plate, no people, no Arenal/wrong-geography markers. Two prior candidate rounds were rejected first: `road.1/2/3.webp`
  (plate / Arenal backdrop / cracked-road implication) and `res.2.webp` (safe but already the hero of
  `how-to-get-around-from-papagayo`, a directly cross-linked sibling article — reuse was explicitly avoided).
- Content: backward-planning framework from flight time, generic "airline's recommended arrival time" framing
  (deliberately no invented Wild-Papagayo-specific airport-buffer number), ~30–45 min Papagayo→LIR general context,
  door-to-door tour-duration explanation (hotel pickup → hotel return, not airport drop-off), four flight-time
  scenarios (Morning/Midday/Late-Afternoon/Evening), fixed-timing and full-day tour warnings, cautious/non-guaranteed
  checkout and luggage-storage guidance, custom/case-by-case tour→airport transfer framing (not a standard inclusion).
  1,638 authored words. 7 FAQs, FAQPage schema confirmed exactly matching visible FAQ text (0 mismatches).
- `recommended_tour_ids` intentionally omitted (not set to `[]`) — logistics-only article, 0 Recommended Tours cards,
  exactly 3 Keep Reading cards (confirmed live). No `.html` internal links, no prices, no age claims.
- No tour/hotel/transfer/destination pages regenerated. Logistics-article cluster (`liberia-airport-transfer-guide`,
  `how-to-get-around-from-papagayo`, `best-half-day-tours-from-papagayo`,
  `liberia-or-san-jos-airport-which-is-better-for-guanacaste`) confirmed unchanged. Global deterministic RSS
  correction still NOT deployed.
- Unrelated pre-existing working-tree drift (hundreds of modified/deleted images, `hotel-generator.ps1`, several
  hotel pages, `tours/fincaaventura.html` deletion) observed in `git status` during this task — confirmed pre-existing,
  not touched, not staged, reported here rather than silently acted on.

## HUB-CANYON-CONGO-LINK-001 = LIVE_VERIFIED (deployed 2026-09-22)

The Day-Trip Hub's Adventure section now links to the existing Canyon vs Congo comparison (Cloudflare
deployment f078f7d2, https://f078f7d2.wild-papagayo.pages.dev), deployed and verified 2026-09-22. No IndexNow.

- One-file public scope: only `blog/which-day-trip-from-papagayo-fits-you.html` modified — one new sentence
  appended to the existing Adventure paragraph, linking to `canyon-adventure-park-vs-congo-trail-which-zip-line-
  is-better-from-papagayo` (anchor text: "Canyon Adventure Park vs Congo Trail comparison"). No new article created.
- Article/sitemap/RSS counts unchanged: 50 live blog articles, 169 sitemap URLs, 50 RSS items. `sitemap.xml`,
  `rss.xml`, `llms.txt` all confirmed byte-identical to baseline — none required a change, since id 53's slug,
  publication date, and excerpt were untouched.
- `../wild-papagayo-deploy-current-baseline` refreshed (this one file only) and remains 517 files; confirmed
  byte-equal to live. The Canyon vs Congo comparison article itself (`canyon-adventure-park-vs-congo-trail-which-
  zip-line-is-better-from-papagayo`) confirmed byte-identical to baseline throughout — not touched.
- Canyon Adventure Park's minimum-age conflict (structured fields say 8; the tour's own public short_description
  and FAQ say 5) remains unresolved and was deliberately NOT surfaced in this edit — no age number appears in the
  new sentence or anywhere else added.
- Process note: the first edit attempt introduced a JSON-escaping bug (unescaped `"` in the new `href` attribute)
  that broke `blog-data.json`'s validity; caught immediately via a validation re-read and fixed in place with a
  targeted byte-level correction, without touching the already-approved hero or losing any other field.
- No tour/hotel/transfer/destination pages regenerated. Global deterministic RSS correction still NOT deployed.

## BLOG-PAPAGAYO-DAY-TRIP-HUB-001 = LIVE_VERIFIED (deployed 2026-09-22)

`/blog/which-day-trip-from-papagayo-fits-you` is live (Cloudflare deployment c836acee,
https://c836acee.wild-papagayo.pages.dev), deployed and verified 2026-09-22. No IndexNow, no indexing request.

- Shipped exactly 5 public files: new article `blog/which-day-trip-from-papagayo-fits-you.html` (id 53, 50th blog
  article, category Trip Planning); `blog/rio-celeste-vs-rincon-de-la-vieja-from-papagayo.html` (+1 Next-nav link
  only, everything else byte-identical); `sitemap.xml` (+1 URL, 169 total); `rss.xml` (+1 item placed first per
  approved order, 50 total, previous 49 items byte-identical/unchanged order — global deterministic RSS correction
  still NOT deployed this session); `llms.txt` (+1 line, inserted directly after the Río Celeste vs Rincón line).
- `../wild-papagayo-deploy-current-baseline` refreshed to 517 files with exactly those 5 files and verified equal to live.
  `../wild-papagayo-deploy-blog-day-trip-hub` was the deployed package (removed after verification).
- Hero: `images/guanacaste-hero.webp` (broad palm-lined bay/coastline, no bucket-specific bias, previously unused as
  any blog hero) — the same image correctly *rejected* for both narrower pairwise-comparison articles earlier this
  session as "too generic/disconnected" is the *correct* choice here, since this is a general regional hub, not a
  destination-specific comparison.
- **This is a decision HUB, not another pairwise comparison.** It is explicitly hotel-agnostic and organizes Papagayo
  day trips by five experience types — Wildlife (Palo Verde River Boat, Hanging Bridges & Sloths), Waterfall/
  Rainforest (Río Celeste), Volcano/Geothermal (Rincón Hiking), Adventure (Canyon Adventure Park + inline canyoning/
  Congo Trail/ATV mentions), Relaxation/Hot Springs (Oropendola & Rio Negro, Miravalles Spa) — with "shorter day"
  handled only as a pointer to `best-half-day-tours-from-papagayo`, not a sixth bucket. No ranking, no universal
  winner, anywhere.
- Explicitly links to `../tour-finder` (confirmed unchanged, byte-identical to baseline) framed as the *interactive*
  matching option, with this article framed as the *written overview* — deliberately not a duplicate quiz/finder.
  Also explicitly differentiates itself from `things-to-do-in-papagayo-costa-rica` (broad inspiration, unchanged) and
  from the hotel-specific "Best Tours From..." article cluster (per-hotel personalization, left entirely untouched).
- `recommended_tour_ids: ["paloverderiverboattour", "celesteriver", "hikingrinconnationalpark", "canyonadventurepark"]`
  → exactly 4 Recommended cards, one per primary bucket. `related_slugs` explicit pin (Things-to-Do, Transportation,
  Half-Day) → exactly 3 Keep Reading cards, matching exactly, 0 unpinned articles affected (confirmed by stability
  simulation before writing).
- No tour/hotel/transfer/destination pages regenerated. Both pairwise comparisons (`palo-verde-vs-rincon-de-la-vieja-
  from-papagayo`, `rio-celeste-vs-rincon-de-la-vieja-from-papagayo` except its approved Next-link), both deep-dive
  articles (`is-rio-celeste-worth-the-drive-from-papagayo`, `can-you-visit-rincon-de-la-vieja-from-papagayo-in-one-day`),
  `things-to-do-in-papagayo-costa-rica`, `best-half-day-tours-from-papagayo`, and `tour-finder.html` all confirmed
  byte-identical live throughout.
- **This closes out the current comparison-cluster arc.** Per the architecture audit that preceded this article, a
  third direct "X vs. Rincón" comparison was explicitly ruled out in favor of this broader hub; any future day-trip
  content should build on this hub/pairwise/deep-dive hierarchy rather than adding more pairwise comparisons.

## BLOG-RIO-CELESTE-VS-RINCON-001 = LIVE_VERIFIED (deployed 2026-09-22)

`/blog/rio-celeste-vs-rincon-de-la-vieja-from-papagayo` is live (Cloudflare deployment b72b449c,
https://b72b449c.wild-papagayo.pages.dev), deployed and verified 2026-09-22. No IndexNow, no indexing request.

- Shipped exactly 5 public files: new article `blog/rio-celeste-vs-rincon-de-la-vieja-from-papagayo.html` (id 52,
  49th blog article, category Trip Planning); `blog/palo-verde-vs-rincon-de-la-vieja-from-papagayo.html` (+1 Next-nav
  link only, everything else byte-identical); `sitemap.xml` (+1 URL, 168 total); `rss.xml` (+1 item placed first per
  approved order, 49 total, previous 48 items byte-identical/unchanged order — global deterministic RSS correction
  still NOT deployed this session); `llms.txt` (+1 line, inserted directly after the Palo Verde vs Rincón line).
- `../wild-papagayo-deploy-current-baseline` refreshed to 516 files with exactly those 5 files and verified equal to live.
  `../wild-papagayo-deploy-blog-rio-celeste-vs-rincon` was the deployed package (removed after verification).
- Hero: `images/july.2.webp` (misty tropical highland forest, no people/landmark/blue-water/fumarole, previously
  unused as any blog hero) — chosen over one-sided candidates (`celeste3.webp`/`celeste4.webp` favoring Río Celeste,
  `rincon4.webp`/`rincon9.webp` favoring Rincón) and over a rejected cloud-forest-look candidate (`july.3.webp`,
  Monteverde-style moss/quetzal signature, wrong geography for Tenorio/Rincón).
- Preference-matching comparison, explicitly no winner: Celeste River Hike (~9h, Moderate, ~6km round trip, waterfall
  viewpoint/blue river/teñideros, fixed 7:30 AM departure, swimming not permitted, geothermal trail feature explicitly
  NOT framed as bathing/soaking) vs. Rincón de la Vieja Hiking (~8h, Easy to Moderate, ~3km Las Pailas Trail,
  fumaroles/mud pots/volcanic vents, Oropendola Waterfall, Tue–Sun, closed Mondays, Classic/Plus hot-springs
  distinction preserved). Waterfall-role nuance made explicit (Río Celeste = destination, Rincón's Oropendola = one
  stop within a broader day) so the article never reduces to "waterfall vs. no waterfall." Route context reused from
  the general Peninsula Papagayo table (Río Celeste 119–152 min, Rincón 102–130 min), not the Bijagua figure and not
  the older, unrelated "~1–1.5h" Rincón-area-falls figure from a prior waterfall roundup.
- `recommended_tour_ids: ["celesteriver", "hikingrinconnationalpark"]` → exactly 2 Recommended cards. `related_slugs`
  explicit pin (Río Celeste worth-the-drive article, Rincón one-day article, Things-to-Do) → exactly 3 Keep Reading
  cards, matching exactly, 0 unpinned articles affected (confirmed by stability simulation before writing).
- No tour/hotel/transfer/destination pages regenerated. `is-rio-celeste-worth-the-drive-from-papagayo` and
  `can-you-visit-rincon-de-la-vieja-from-papagayo-in-one-day` confirmed byte-identical live throughout.
- **This is intended as the LAST direct "X vs. Rincón de la Vieja" comparison article for now** — two such articles
  now exist (Palo Verde vs. Rincón and Río Celeste vs. Rincón) and a third would start to feel templated. Future
  comparison-style content should favor a broader decision hub or a different format rather than another pairwise
  "X vs. Rincón" article.

## BLOG-PALO-VERDE-VS-RINCON-001 = LIVE_VERIFIED (deployed 2026-09-22)

`/blog/palo-verde-vs-rincon-de-la-vieja-from-papagayo` is live (Cloudflare deployment 569b2c7a,
https://569b2c7a.wild-papagayo.pages.dev), deployed and verified 2026-09-22. No IndexNow, no indexing request.

- Shipped exactly 5 public files: new article `blog/palo-verde-vs-rincon-de-la-vieja-from-papagayo.html` (id 51,
  48th blog article, category Trip Planning); `blog/how-to-get-around-from-papagayo.html` (+1 Next-nav link only,
  everything else byte-identical); `sitemap.xml` (+1 URL, 167 total); `rss.xml` (+1 item placed first per approved
  order, 48 total, previous 47 items byte-identical/unchanged order — global deterministic RSS correction still NOT
  deployed this session); `llms.txt` (+1 line, inserted directly after the Transportation line).
- `../wild-papagayo-deploy-current-baseline` refreshed to 515 files with exactly those 5 files and verified equal to live.
  `../wild-papagayo-deploy-blog-palo-verde-vs-rincon` was the deployed package (removed after verification).
- Hero: `images/hongo_3.webp` (neutral tropical forest trail, no people/wildlife/landmark, previously unused as any
  blog hero). Rejected first: `images/guanacaste-hero.webp` (neutral but too generic/beach-oriented, disconnected
  from either tour's actual subject). Two Rincón-specific candidates (`rincon4.webp`, `rincon9.webp`) were identified
  but not needed since a genuinely balanced option existed — consistent with the one-sided-hero rule.
- Article is a preference-matching comparison, explicitly no winner: Palo Verde River Boat (~6h, Easy, private
  90-minute riverboat, tide-set departure, wildlife never guaranteed) vs. Rincón de la Vieja Hiking (~8h, Easy to
  Moderate, ~3km Las Pailas Trail, fumaroles/mud pots/volcanic vents, Oropendola Waterfall, Tue–Sun, closed Mondays).
  Hot springs explicitly flagged as Plus-tier only, not standard on the Hiking tour, never conflated with the separate
  Buena Vista Mega Combo. General Papagayo route-time context reused verbatim from the Transportation article
  (Palo Verde 96–123 min, Rincón 102–130 min), labeled general planning figures, not hotel-specific.
- `recommended_tour_ids: ["paloverderiverboattour", "hikingrinconnationalpark"]` → exactly 2 Recommended cards.
  `related_slugs` explicit pin (Palo Verde comparison article, Rincón one-day article, Half-Day guide) → exactly
  3 Keep Reading cards, matching exactly, 0 unpinned articles affected (confirmed by stability simulation before writing).
- No tour/hotel/transfer/destination pages regenerated. `palo-verde-tours-from-papagayo-river-boat-or-el-viejo` and
  `can-you-visit-rincon-de-la-vieja-from-papagayo-in-one-day` confirmed byte-identical live throughout (linked as the
  deeper single-destination guides, not modified or re-derived from).

## LLMS-LA-FORTUNA-BACKFILL-001 = LIVE_VERIFIED (deployed 2026-09-22)

The KNOWN LLMS BACKLOG noted in BLOG-PAPAGAYO-TRANSPORTATION-001 below is FIXED: `llms.txt` now includes
`how-many-days-la-fortuna` (Cloudflare deployment 932b9b9b, https://932b9b9b.wild-papagayo.pages.dev),
deployed and verified 2026-09-22. No IndexNow, no indexing request.

- One-file public scope: only `llms.txt` modified (+1 line, inserted between the Secrets Papagayo and Transportation
  lines to match actual chronological deploy order). No HTML regenerated, no sitemap change, no RSS change.
- Article/sitemap/RSS counts unchanged: 47 live blog articles, 166 sitemap URLs, 47 RSS items.
- `../wild-papagayo-deploy-current-baseline` refreshed (llms.txt only) and remains 514 files; confirmed byte-equal to live.
- Global deterministic RSS correction still NOT deployed this session.

## BLOG-PAPAGAYO-TRANSPORTATION-001 = LIVE_VERIFIED (deployed 2026-09-22)

`/blog/how-to-get-around-from-papagayo` is live (Cloudflare deployment e8312ad3, https://e8312ad3.wild-papagayo.pages.dev),
deployed and verified 2026-09-22. No IndexNow, no indexing request.

- Shipped exactly 5 public files: new article `blog/how-to-get-around-from-papagayo.html` (id 50, 47th blog article);
  `blog/how-many-days-la-fortuna.html` (+1 Next-nav link only, everything else byte-identical); `sitemap.xml` (+1 URL,
  166 total); `rss.xml` (+1 item placed first per approved order, 47 total, previous 46 items byte-identical/unchanged
  order — global deterministic RSS correction still NOT deployed this session); `llms.txt` (+1 line for the new article).
- `../wild-papagayo-deploy-current-baseline` refreshed to 514 files with exactly those 5 files and verified equal to live.
  `../wild-papagayo-deploy-blog-papagayo-transportation` is the deployed package.
- Hero: `images/res.2.webp` (black SUV in a driveway outside a modern house, no plate/branding/landmark, previously
  unused as any blog hero). Two earlier hero candidates were tested and rejected before this one: `images/road.1.webp`
  (plate too prominent, no actual road visible despite the article's transport theme) and `images/foto-van-home.webp`
  (backdrop is identifiably Arenal Volcano/Lake Arenal — wrong geography for a Papagayo article, also flagged for
  stock-photo-style provenance concern).
- Article owns POST-ARRIVAL Papagayo transportation/day-trip logistics only; `liberia-airport-transfer-guide` remains
  the owner of LIR-arrival logistics and was not modified (confirmed byte-identical live). Three transportation models
  defined: private transfer (point A→B), private-driver-style day (linked to the existing non-standardized
  `private-driver-from-papagayo-waterfall-lunch-half-day` example), private tour (transportation + certified bilingual
  guide + defined itinerary). General Papagayo/Peninsula Papagayo route table (Rincón 102–130, Palo Verde 96–123,
  Bijagua 104–132, Río Celeste 119–152, La Fortuna/Arenal 180–230 min) explicitly labeled general context, not
  hotel-specific. Monteverde kept out of the measured table (general "~3h each way / ~12h day" context only).
- `related_slugs` explicit pin: `liberia-airport-transfer-guide`, `how-many-days-la-fortuna`, `best-half-day-tours-from-papagayo`
  — Keep Reading cards confirmed matching exactly, 0 unpinned articles affected.
- `tour_ids: []`, `recommended_tour_ids` intentionally OMITTED (not `[]` — the generator hard-errors on an empty array
  but renders cleanly with the key absent) → 0 Recommended Tour cards, no Recommended Tours section. This is intentional,
  not a bug; do not add tour IDs to "fix" it without a new editorial decision.
- **KNOWN LLMS BACKLOG (pre-existing, not caused by this deploy) — FIXED 2026-09-22, see LLMS-LA-FORTUNA-BACKFILL-001 above:**
  `how-many-days-la-fortuna` had no entry anywhere in `llms.txt`, confirmed still missing after this deploy. Not backfilled
  here per explicit instruction at the time — needs a future
  dedicated task.
- No transfer/tour/hotel/destination pages regenerated. `private-driver-from-papagayo-waterfall-lunch-half-day` confirmed
  byte-identical live (linked as the concrete private-driver example only). Other 45 pre-existing blog articles confirmed
  byte-identical to their pre-deploy state (spot-checked plus full-directory diff in package prep).

## BLOG-BABY-NO-CAR-001 = LIVE_VERIFIED

`/blog/costa-rica-with-a-baby-without-rental-car` is live (Cloudflare deployment d8be42b3, https://d8be42b3.wild-papagayo.pages.dev),
deployed 2026-09-20 21:00 -0600 and verified. Observation clock started 2026-09-20 21:02 -0600. No IndexNow, no indexing request.

- Shipped: exactly 6 files (new article, +1 Continue Planning link on the 11-month-old article, LIR guide and La Fortuna recap, `rss.xml` +1 item, `sitemap.xml` +1 URL).
  `../wild-papagayo-deploy-current-baseline` was refreshed with those 6 files and equals live again; `../wild-papagayo-deploy-baby001` is the deployed package.
- `llms.txt` unchanged on purpose (md5 e1f68d11...). ENTITY-TRANSFER-001, ENTITY-TRANSFER-002 and BLOG-URL-NORMALIZATION-001 unchanged, clocks not reset.
- Legal status PARTIALLY_VERIFIED (Decreto 38239-MOPT art. 1; applicability to a private tourist transfer van unresolved). Child-seat policy is owner-confirmed.
- Owner fact recorded: Wild Papagayo offers private transportation between La Fortuna and Guanacaste, subject to availability and requested destination.
- The old regeneration warning (Keep Reading / Next reshuffle) is resolved at source by the determinism fix below.
- Record: `seo-intelligence/experiments/BLOG-BABY-NO-CAR-001.json`.

## Ostional P1 = LIVE_VERIFIED (deployed 2026-09-21)

Cloudflare deployment bc164cd6 (https://bc164cd6.wild-papagayo.pages.dev), exactly 2 files on top of the verified baseline: the improved Ostional article and the
`things-to-do-in-papagayo-costa-rica` Next link to the baby article. `rss.xml`, `sitemap.xml`, `llms.txt` and all other pages unchanged. No IndexNow, no indexing request.
`../wild-papagayo-deploy-current-baseline` was refreshed with exactly those 2 HTML files and equals live. Baby001 folder is the previous deployed package.
Open note: the tour page says "Best Season August to November (arribada)"; the article says arribadas occur year-round (larger in the rainy season). Classification intentionally unresolved; tour page untouched.

## Riu Palace article = LIVE_VERIFIED (deployed 2026-09-21)

`/blog/best-tours-from-riu-palace-costa-rica` is live (Cloudflare deployment 63a175d6-9c4a-40d9-9f97-7decf498b650, https://63a175d6.wild-papagayo.pages.dev). Blog is now 40 articles.
Shipped exactly 5 public files: the new article, the baby article (Next link only), `sitemap.xml` (+1, now 159 URLs), `rss.xml` (+1 manual item, now 40 items) and `llms.txt` (+1 line).
The new RSS item uses the correct UTC pubDate; the 39 older items are byte-unchanged and still carry the older shifted pubDates. The deterministic RSS correction is still NOT deployed.
The Riu Palace hotel page was NOT regenerated (its Travel Insights will list the article only after a future scoped hotel regeneration). Four Seasons and Andaz articles unchanged: they now hold explicit `related_slugs` pins in `blog-data.json`.
`../wild-papagayo-deploy-current-baseline` was refreshed with those 5 files (507 files) and equals live. No IndexNow or indexing request yet. Next content candidate: Nekajui or Waldorf.

## Nekajui article = LIVE_VERIFIED (deployed 2026-09-21)

`/blog/best-tours-from-nekajui` is live (Cloudflare deployment 6fe752ae-c776-41b6-9456-7180e0475758, https://6fe752ae.wild-papagayo.pages.dev). Blog is now 41 articles.
Shipped exactly 5 public files: the new article, the Riu Palace article (Next link to Nekajui only), `sitemap.xml` (+1, now 160 URLs), `rss.xml` (+1 manual item, now 41 items) and `llms.txt` (+1 line).
The article's differentiator is measured Nekajui drive times from the Nekajui private-tours landing (Buena Vista, Rincón/Las Pailas, Bijagua, Río Celeste, Arenal); Hanging Bridges & Sloths and Miravalles have none, Monteverde is general Papagayo context. Palo Verde and Hacienda Aromal are excluded until their source conflicts are reconciled. Hero is `images/rincon5.webp` (local tour-gallery asset; original photographer unrecorded).
The RSS deterministic correction is still NOT deployed (new items use correct UTC pubDates, the 40 older items keep the older shifted values). The Nekajui hotel page was NOT regenerated (Travel Insights will list the article only after a scoped hotel regeneration); the Nekajui private-tours landing is unchanged.
`../wild-papagayo-deploy-current-baseline` was refreshed with those 5 files (508 files) and equals live. `blog-data.json`, `blog-generator.ps1` and this file stay local/untracked. No IndexNow or indexing request yet. Next content candidate: Waldorf.

## Waldorf article = LIVE_VERIFIED (deployed 2026-09-21)

`/blog/best-tours-from-waldorf-astoria-costa-rica` is live (Cloudflare deployment 9fed6168-8a4c-4ace-b4df-1560a41441d2, https://9fed6168.wild-papagayo.pages.dev, Production/main). Blog is now 42 articles.
Shipped exactly 5 public files: the new article, the Nekajui article (Next link to Waldorf only), `sitemap.xml` (+1, now 161 URLs), `rss.xml` (+1 manual item, now 42 items, order Waldorf, Nekajui, Riu Palace) and `llms.txt` (+1 line).
The RSS deterministic correction is still NOT deployed (the new item uses a correct UTC pubDate; the 41 older items are byte-unchanged). The Waldorf hotel page was NOT regenerated (Travel Insights will list the article only after a scoped hotel regeneration).
`../wild-papagayo-deploy-current-baseline` was refreshed with those 5 files (509 files) and equals live. `blog-data.json`, `blog-generator.ps1` and this file stay local/untracked. No IndexNow or indexing request yet. Next content candidate: to be chosen after this cycle.

## Palo Verde article = LIVE_VERIFIED (deployed 2026-09-21)

`/blog/palo-verde-tours-from-papagayo-river-boat-or-el-viejo` is live (Cloudflare deployment 5c8ab614-9d63-40ac-9ad2-1699b87700e6, https://5c8ab614.wild-papagayo.pages.dev, Production/main). Blog is now 43 articles; sitemap 162 URLs; RSS 43 items (order Palo Verde, Waldorf, Nekajui, Riu Palace).
Shipped exactly 7 public files: the new article, Andaz, Riu Guanacaste and Waldorf articles, `sitemap.xml` (+1), `rss.xml` (+1 manual item) and `llms.txt` (+1 line). The RSS deterministic correction is still NOT deployed (41+ older items keep the older shifted pubDates). Tour pages and hotel pages were NOT regenerated.
Andaz and Riu Guanacaste were normalized to Palo Verde River Boat ~6 h / Easy (old ~4 h / Moderate removed); Riu's fixed-afternoon/pool wording was removed and tide-set departure framed. Waldorf gained Next -> Palo Verde. Hero is `images/paloverde3.webp` (boat-billed heron).
Four Seasons was NOT touched: its family / all-ages wording for the River Boat conflicts with the tour page (min age 8 vs all ages) and stays unresolved.
Unresolved ops questions: (1) River Boat minimum age, (2) whether the El Viejo boat is private to the group, (3) whether El Viejo departures are tide-dependent. The article deliberately excludes all three claims.
`../wild-papagayo-deploy-current-baseline` was refreshed with those 7 files (510 files) and equals live. `blog-data.json`, `blog-generator.ps1` and this file stay local/untracked. No IndexNow or indexing request yet.

## Half-Day article = LIVE_VERIFIED (deployed 2026-09-21)

`/blog/best-half-day-tours-from-papagayo` is live (Cloudflare deployment 95f506c5-0a5d-4b07-8bc2-cd425266e92f, https://95f506c5.wild-papagayo.pages.dev, Production/main). Blog is now 44 articles; sitemap 163 URLs; RSS 44 items (order Half-Day, Palo Verde, Waldorf, Nekajui, Riu Palace).
Shipped exactly 5 public files: the new article, the Palo Verde article (Next link to Half-Day only), `sitemap.xml` (+1), `rss.xml` (+1 manual item) and `llms.txt` (+1 line). The RSS deterministic correction is still NOT deployed. Tour pages were NOT regenerated.
Seven-tour shortlist: Waterfall & Las Pumas, Palo Verde River Boat, Congo Trail Half-Day Adventure, Horseback Riding at Hacienda Aromal, Waterfall Canyoning & Tubing, Colorado River Rafting, Congo Trail Canopy & Extreme Zip Line. Oropendola (ops hold on price/duration) and Canyon Adventure Park (internal age conflict) were excluded; ATV Mountain Ride appears only as a brief separate 4-hour note. No ages are stated anywhere in the article. Hero is `images/horsebackaromal1.webp`.
`private-driver-from-papagayo-waterfall-lunch-half-day` is linked as a custom, non-tour alternative and was not modified.
Unresolved Palo Verde ops questions remain unchanged: River Boat minimum age, whether the El Viejo boat is private to the group, and whether El Viejo departures are tide-dependent.
`../wild-papagayo-deploy-current-baseline` was refreshed with those 5 files (511 files) and equals live. `blog-data.json`, `blog-generator.ps1` and this file stay local/untracked. No IndexNow or indexing request yet.

## Secrets Papagayo article = LIVE_VERIFIED (deployed 2026-09-21)

`/blog/best-tours-from-secrets-papagayo-costa-rica` is live (Cloudflare deployment 0c889a0a-ad08-4418-ad44-52311f941abb, https://0c889a0a.wild-papagayo.pages.dev, Production/main). Blog is now 45 articles; sitemap 164 URLs; RSS 45 items (order Secrets, Half-Day, Palo Verde, Waldorf, Nekajui, Riu Palace).
Shipped exactly 5 public files: the new article, the Half-Day article (Next link to Secrets only), `sitemap.xml` (+1), `rss.xml` (+1 manual item) and `llms.txt` (+1 line). The RSS deterministic correction is still NOT deployed. No hotel or tour pages were regenerated.
Six-tour shortlist: Hanging Bridges & Sloths, Celeste River Hike & Tenorio, Rincon de la Vieja Hiking, Buena Vista Mega Combo, Palo Verde River Boat, Costa Rica Highlights. Hotel geography is Golfo de Papagayo / Papagayo area only (never Peninsula Papagayo); LIR is 22-28 min (20.7 km). No ages, adults-only or family claims. Hero is `images/rincon3.webp` (howler monkeys).
The Secrets hotel page was deployed unchanged from the verified baseline copy; the known working-tree one-blank-line drift on that page was NOT used and was NOT deployed, and remains local/untracked only.
Unresolved Palo Verde ops questions remain unchanged: River Boat minimum age, whether the El Viejo boat is private to the group, and whether El Viejo departures are tide-dependent.
`../wild-papagayo-deploy-current-baseline` was refreshed with those 5 files (512 files) and equals live. `blog-data.json`, `blog-generator.ps1` and this file stay local/untracked. No IndexNow or indexing request yet.

## BLOG-LA-FORTUNA-DURATION-001 = LIVE_VERIFIED (deployed 2026-09-21)

`/blog/how-many-days-la-fortuna` is live (Cloudflare deployment a353cd8c-ca1b-41c9-a7c0-074fc40cb335, https://a353cd8c.wild-papagayo.pages.dev, Production/main). Blog is now 46 articles; sitemap 165 URLs; RSS 46 items. Observation clock started at this deploy's verification.
Shipped exactly 6 public files: the new article, two existing La Fortuna articles (`arenal-hanging-bridges-and-a-waterfall-in-one-day` and `la-fortuna-without-a-rental-car-an-honest-trip-recap`, each +1 inbound-link sentence only), `best-tours-from-secrets-papagayo-costa-rica` (Next-link only, newest-article pattern), `sitemap.xml` (+1) and `rss.xml` (+1 manual item). `llms.txt` was intentionally NOT modified (NO_CHANGE, per instruction).
Both edited articles also gained explicit `related_slugs` pins in `blog-data.json` (matching their pre-existing Keep Reading order exactly) so the new article's shared destination/tour tags don't silently reshuffle their fallback-scored Keep Reading cards; live HTML for both is otherwise unchanged from baseline.
The article is a stay-duration decision guide (nights vs. full days, arrival/departure/transfer-day framing, 2/3/4/5+ night treatments, a 3-in-1 hanging-bridges/volcano-hike/safari-float FAQ only, no dedicated combo article). It is the pillar for the La Fortuna cluster per `seo-intelligence/reports/la-fortuna-stay-duration-opportunity-analysis.md`. Hero is `images/arenalhotsprings4.webp` (Lake Arenal landscape).
ENTITY-TRANSFER-001, ENTITY-TRANSFER-002, BLOG-URL-NORMALIZATION-001 and BLOG-BABY-NO-CAR-001 all confirmed unchanged live (protected assets byte-identical to pre-deploy baseline); no observation clock was reset.
`../wild-papagayo-deploy-current-baseline` was refreshed with those 6 files (513 files) and equals live. `blog-data.json`, `blog-generator.ps1` and this file stay local/untracked. No IndexNow or indexing request yet. Measurement checkpoints planned for Day 0/7/14/28 (research only, not started).
Known pre-existing, unrelated working-tree drift remains (noted in the research and build phases): the local `wild-papagayo/llms.txt` file is a stale snapshot; it was not deployed and not used as a comparison source for this deploy.

## Blog generator determinism (source checkpoint, local and untracked in git)

`blog-generator.ps1` is deterministic: stable Keep Reading and Recommended ranking, deterministic RSS code (explicit UTC pubDate, stable order, write-if-changed), `-Slug <slug>` single-article mode,
`-RefreshRss`, up-front pin validation. `blog-data.json` has 24 `related_slugs` and 19 `recommended_tour_ids` pins. These files and this note are untracked, so no commit represents them.
The corrected `rss.xml` is NOT deployed (all 39 pubDates change; review separately). Live and baseline `rss.xml` still use the old output.
Next content phase can begin. For blog work use `-Slug` in a TEMP copy and ship only intended HTML.

## Transfer navigation audit (research only, IMPLEMENTATION NOT_STARTED)

`seo-intelligence/reports/transfer-navigation-hub-architecture-audit.md`: improve `/transport` only, no `/transfers` hub yet, keep the header.
Phase 1 (`/transport` route cards + visible FAQ, La Fortuna destination CTA) waits for the ENTITY-TRANSFER-002 checkpoint. Header/footer changes also rewrite the measured landings, so they wait too.

## /transport "Private Transportation During Your Stay" = OWNER_DECISIONS_FINAL / IMPLEMENTATION_DEFERRED

OWNER FACTS = CONFIRMED. CONTENT DECISIONS = APPROVED. GROCERY OPTION = C / REQUEST-BASED. LUNCH MEAL = TRAVELER
PAYS. COVERAGE WORDING = APPROVED CONSERVATIVE COVERAGE. IMPLEMENTATION = DEFERRED. DATAFORSEO = NOT NEEDED.
No open owner questions remain.

- Action (after checkpoints below): MAJOR SECTION + VISIBLE FAQ on `/transport` (no new landing). NOT implemented;
  `transport.html` untouched.
- **Two checkpoints gate implementation** (both re-verified 2026-09-29, not assumed):
  - ENTITY-TRANSFER-002 Day 28 = **2026-10-18** (holds `transport.html` and `blog/liberia-airport-transfer-guide.html`, both MD5-pinned).
  - BLOG-BABY-NO-CAR-001 Day 28 = **~2026-10-19** (its own deploy added a link to `blog/costa-rica-with-an-11-month-old-where-should-you-stay.html`, which is why that article is also blocked, not just ET-002's file list).
- Final facts (lunch stop, driver wait included, meal paid by traveler; grocery = request-based, no automatic fee;
  multi-leg coordinated, one price or per leg; additional stops quoted per request, no universal free wait; child
  seats free, age+weight, own seat OK; conservative coverage statement) stored in `knowledge/transportation.json`
  -> `private-airport-transfer.operating_facts` (`status: OWNER_CONFIRMED_FINAL`).
- Final plan, re-verified conflict audit, exact C1 form-change spec (`transport.src.js`/`transport.html` diff),
  approved C2-C5 replacement wording, final section copy and final 7 FAQs:
  `seo-intelligence/reports/transport-private-transportation-during-stay-plan.md`.
- **Finding this task: C1-C5 are all currently blocked** — C1 by explicit instruction, C2-C4 because
  `liberia-airport-transfer-guide.html` is inside ET-002's measured/MD5-pinned scope, C5 because the 11-month-old
  article is inside BLOG-BABY-NO-CAR-001's own live observation window. Nothing was safe to correct in production
  this task; no production file was edited.
- Bubu gap (not built): `assistant-knowledge-generator.ps1` does not read `knowledge/transportation.json` at all.
- **Evidence logged 2026-10-02 (no reopening, gate unchanged):** a traveler signal (rental-car-vs-private-transfer
  decision for a multi-destination trip, illustrative route LIR -> La Fortuna -> Monteverde -> Guanacaste -> LIR)
  supports a candidate **"Multi-Destination Private Journeys"** subsection within this same planned `/transport`
  section — not a new URL, not a reopening of the approved content/gate. Three-model decision framework recorded
  as a candidate (rental car for the whole trip / private transportation between destinations / hybrid), to be
  evaluated at the existing checkpoint alongside the already-approved copy. Also recorded: a future editorial
  distinction between a transfer with a practical stop (lunch, grocery — already an approved fact) and a transfer
  combined with a multi-hour excursion (not the same product; not promised now). Route-landing guard reaffirmed:
  do not auto-create `LIR-to-La-Fortuna`, `La-Fortuna-to-Monteverde`, `Monteverde-to-{Flamingo,Papagayo,Tamarindo}`
  or similar from this signal — `/transport` remains the sole hub until route-specific evidence justifies a child
  page. Full detail: `seo-intelligence/reports/transport-private-transportation-during-stay-plan.md`'s 2026-10-02
  addendum. No production file touched; DataForSEO $0.00.
- **Additional traveler signal logged 2026-10-16 (demand observation only, gate unchanged):** a further traveler
  question (rental car vs Uber / private / shared transportation) supports the same decision above. It is recorded as
  a demand observation, NOT a validated high-volume SEO opportunity: GSC (2026-10-12) shows only small transport-query
  volumes (e.g. "is there uber in liberia costa rica" 20 impressions at position 12.8), and no measurement supports
  any AI-answer-value rating. Owners preserved: `/transport` and its planned **"Multi-Destination Private Journeys"**
  subsection remain the content owner; `/blog/costa-rica-without-a-car-guide` keeps the no-car itinerary angle; the
  existing Uber article (`is-uber-available-at-liberia-airport-what-to-know`) keeps the airport-specific intent. No
  new URL; previously consolidated articles (e.g. `rental-car-vs-private-driver-in-guanacaste-honest-guide`, redirected
  to the transportation category) are NOT reactivated. The existing `/transport` implementation block above stays in
  place unchanged. No production file touched; DataForSEO $0.00.
- **Commercial demand observation logged 2026-10-18 - custom private day-tour inquiry (demand observation only; no
  content action):** a traveler asked for a private customized day tour with a driver covering beaches, local food,
  coffee shops and shopping, for four people; accommodation location not yet known. Recorded as a COMMERCIAL
  follow-up, not an editorial opportunity and not a validated SEO opportunity: GSC (2026-10-12) shows no custom-day-tour
  query (closest are "hire private driver costa rica"-type queries at 1-2 impressions), search volume is unconfirmed,
  and no measurement supports any AI-answer-value rating. Ownership and restrictions unchanged: `/transport` and its
  planned "Multi-Destination Private Journeys" subsection remain the content owner; no new URL, product, route,
  price or commercial promise is created, and no generic "private custom day tour" landing page. Handling rule for any
  reply: ask for the accommodation location first; if it is in Guanacaste, a proposal must be built only from stops and
  services confirmed with operations - the repo has no first-party records of food, coffee or shopping stops, so none
  may be presented as offered until confirmed. Existing overlap for reference: private-transport content,
  `/private-tours/peninsula-papagayo`, Playa Hermosa / Playas del Coco destination pages (the Coco page has no custom or
  private-route content today). No production file touched; DataForSEO $0.00.
- **CRM/product track (separate from the content track above, logged same date):** this signal also strengthens
  a standing, unimplemented product hypothesis for `wild-papagayo-ops` (the CRM, a different codebase) — a
  Journey-level multi-leg quoting concept (Customer -> Journey -> Passengers -> Legs -> Dates -> Origin/
  Destination -> Accommodation/Pickup -> Optional Stops -> Optional Experiences -> Leg Price -> Journey Total).
  Recorded as a product/data-model hypothesis only — no CRM schema, migration, or code change authorized or made.
  Ten open product-design questions (Journey as new entity vs. existing Quote/Trip reuse, multi-leg/multi-date
  representation, optional-stop/experience modeling, per-leg vs. journey-total pricing, partial
  modification/cancellation, driver/vehicle scheduling across dates, whether the existing Service model already
  covers part of this) deferred to a future dedicated product-design session — see the extended cross-reference
  in `seo-intelligence/reports/lir-itinerary-cluster-opportunity-analysis.md` (2026-09-29 addendum, part C,
  extended 2026-10-02). Content publication and CRM development are explicitly independent; neither blocks the
  other.

## Playas del Coco solo / long-stay / everyday-life = RESEARCH PENDING, IMPLEMENTATION NOT_STARTED (logged 2026-10-04)

A signal about living 3-6 weeks in Playas del Coco as a solo traveler (everyday life, mobility, car-free stay,
social life) was logged for research only. **No architecture is decided:** owner, URL and page type (new page vs.
section vs. child) are open. Existing-content check found no long-stay content on the site; the Coco
solo-female night-safety post owns night safety only, not this topic. Next step: validate demand, intent and
overlap from existing signals first. DataForSEO: no calls until endpoint, price and budget are verified.
No production file, post or destination record touched. Separate from the Tabacon vs Baldi dossier. Full record:
`seo-intelligence/reports/coco-solo-long-stay-opportunity-analysis.md`.

## LIR itinerary cluster (LIR -> La Fortuna -> Tamarindo -> LIR) = DEFER STANDS (2nd Facebook signal logged 2026-09-29)

A second Facebook traveler question (airport -> La Fortuna -> Tamarindo -> airport, plus excursions and a
possible single combined quote) matches the trip class already researched and DEFERRED in
`seo-intelligence/reports/lir-itinerary-cluster-opportunity-analysis.md`. **The existing DEFER stands**; the
note's suggested "MERGE / ADD MAJOR SECTION" was checked against that dated decision and not actioned — see the
2026-09-29 addendum at the end of that report for the full reasoning, the GSC check (NO_RELEVANT_EVIDENCE / the
export doesn't cover "now"), and why. Checkpoint unchanged: ~2026-10-20 (`BLOG-COSTA-RICA-WITHOUT-CAR-001` Day 28).
Two owner-input items are now concrete for that checkpoint: (1) whether WP wants a single quote that bundles
transfers + optional excursions in one request (separate from the already-confirmed multi-leg-transportation
fact in `knowledge/transportation.json`) — a product/estimator feature, unscoped, not the same thing as content;
(2) Rincón/Monteverde stay day-trip-only (unchanged guardrail). No production file touched. DataForSEO: $0.00.

## LIR itinerary cluster = DEFER STANDS (3rd signal logged 2026-10-02)

A third traveler question (first trip, 10-12 days, no rental car, La Fortuna + Monteverde + Guanacaste,
wildlife/adventure/cloud-forest/beach, explicit "less touristy" framing) matches the same trip class already
researched and DEFERRED twice in `seo-intelligence/reports/lir-itinerary-cluster-opportunity-analysis.md`. **The
existing DEFER stands** — see the 2026-10-02 addendum at the end of that report for the full reasoning.
Checkpoint unchanged: ~2026-10-20 (`BLOG-COSTA-RICA-WITHOUT-CAR-001` Day 28); next evidence is real GSC data,
not DataForSEO. New finding this task: the signal's own framing (Monteverde as a third sequential overnight
base) conflicts with already-published, settled guidance (`is-monteverde-worth-a-day-trip-from-guanacaste` —
Monteverde is a ~3h-each-way day trip, "usually not worth it" for short stays/young children, never an
overnight leg) — a premise conflict to resolve inside Option D if it's ever built, not a reason to build
anything now. Also recorded: `destinations/monteverde.html` has no transportation/logistics content (empty
`transfer_time`, no FAQ) and no link to the day-trip decision article — classified
`MONTEVERDE_LOGISTICS_INTEGRATION = FUTURE MICRO-UPDATE CANDIDATE`, not implemented (no invented transfer time,
no repositioning as a base). No production file, `blog-data.json`, template, generator or HTML touched.
DataForSEO: $0.00.

## LIR itinerary cluster = DEFER STANDS (4th signal logged 2026-10-02)

A fourth traveler question (2-3 week first trip, teenagers, green season/July-August, SJO routing, surfing,
"what should Guanacaste replace?" rather than "should we add Guanacaste") matches the same trip class already
researched and DEFERRED three times in `seo-intelligence/reports/lir-itinerary-cluster-opportunity-analysis.md`.
**The existing DEFER stands** — see the 2026-10-02 fourth-signal addendum at the end of that report. Checkpoint
unchanged: ~2026-10-20; next evidence is real GSC data, not DataForSEO. New dimensions recorded for that
checkpoint: `TEENAGER_TRAVEL_LAYER` (supporting dimension, not yet classified as add-section/profile-layer/
internal-link/no-action), `SJO_ROUTING` (first signal in this cluster not centered on LIR), and the sharper
Guanacaste-as-consolidation framing (one beach base replacing a hotel change, not automatically adding one —
no universal claim, no "Why Guanacaste Should Replace X" content). Also recorded a conservative editorial
principle on long-range ENSO forecasting: NOAA's own AMJ 2027 probabilities already show significant forecast
weakening from the current strong El Niño, so no future itinerary content should characterize July/August 2027
conditions as a known "Super El Niño" consequence — revisit official seasonal forecasts closer to travel instead.
No production file, `blog-data.json`, template, generator or HTML touched. DataForSEO: $0.00.

## LIR itinerary cluster = DEFER STANDS (5th signal logged 2026-10-16)

A fifth traveler question (family, ~10 days, in and out of LIR, wildlife-first, willing to drive to Manuel Antonio
because they believe it is needed for good wildlife) matches the same trip class already researched and DEFERRED
three times (`seo-intelligence/reports/lir-itinerary-cluster-opportunity-analysis.md`,
`lir-family-itinerary-architecture-analysis.md`). Analysis:
`seo-intelligence/reports/lir-wildlife-family-10day-manuel-antonio-opportunity-analysis.md`. **The existing
standalone-page DEFER stands. No new URL.** Owner decisions (2026-10-16):
- **Content owner:** `/blog/costa-rica-without-a-car-guide`. Direction when allowed: expand it with a
  traveler-priority-first wildlife destination-choice framework (first the experience the family wants, then
  destinations and route); link to existing articles (LIR vs SJO, LIR-to-Arenal drive times, how-many-days-La-Fortuna,
  sloth comparison, Bijagua destination, baby/no-car) instead of restating them.
- **Timing:** do NOT modify the owner page before the Day 28 checkpoint of `BLOG-COSTA-RICA-WITHOUT-CAR-001`
  (~2026-10-20). After it: review fresh GSC evidence, experiment results and existing page coverage before proposing
  any expansion. Nothing is implemented now.
- **Manuel Antonio:** may be mentioned as an honest planning decision point. Wild Papagayo does not operate there:
  never imply commercial coverage or available services; no Manuel Antonio drive times, fees, wildlife claims or
  "better than" comparisons without a verified source.
- **ICT / Bijagua birdwatching:** do not publish or attribute any such claim until the exact official ICT source
  has been retrieved, read and verified. If no suitable source exists, omit the claim. (The signal's note carried no
  retrievable citation; `destinations/bijagua.html` makes no birdwatching claim today.)
- **DataForSEO:** no paid research authorized. The proposed ~$0.07 research (search volume + one SERP/AIO check for
  Liberia airport to Manuel Antonio phrasing) stays unapproved, separate from Pilot V1 and from its cap.
- **Evidence now:** GSC export 2026-10-12 shows near-zero direct demand (e.g. "10 days in costa rica without a car" 5
  impressions at position 7.6; Manuel Antonio queries 1-2 impressions); the query table is partial. No pilot AI
  prompt tested this question, so the "AI-answer value" claim is a hypothesis.
- **Untouched:** `blog-data.json`, all website pages, production assets, deployments. DataForSEO: $0.00.

## WILDLIFE-ECOSYSTEM-CHOICE = DEFERRED OPPORTUNITY (logged 2026-10-16, nothing implemented)

Traveler signal: wildlife/birds/rainforest from Playa Hermosa, Guanacaste (wildlife assumed to mean rainforest).
Analysis: `seo-intelligence/reports/playa-hermosa-wildlife-ecosystem-choice-opportunity-analysis.md`. **No new URL.**
Owner decisions (2026-10-16):
- **Decision owner:** `/blog/which-day-trip-from-papagayo-fits-you`. The ecosystem framing belongs primarily there.
  `/blog/palo-verde-vs-rincon-de-la-vieja-from-papagayo` stays the detailed comparison page.
- **Information-gain concept:** rainforest is not the only ecosystem for wildlife experiences in Guanacaste. Every
  ecosystem/wildlife claim must be validated against existing verified first-party tour records before publication.
- **Playa Hermosa pages** (`destinations/playa-hermosa`, `blog/playa-hermosa-guanacaste-with-kids`): explain realistic
  wildlife excursion choices from that base and link to the existing owners; they must not restate destination content.
- **Architectural opportunity (recorded, NOT implemented):** zero internal links in either direction between the Playa
  Hermosa pages and the wildlife owners (hub, Palo Verde vs Rincon, sloth comparison, `destinations/bijagua`). Links may
  be proposed later; any change needs separate approval.
- **Protected pages:** `destinations/bijagua` and `tours/slothadventure` (BIJAGUA-SLOTH-001) must not be modified;
  links TO them may be proposed.
- **Generator investigation (open, nothing edited):** the generated `destinations/playa-hermosa.html` travel-score card
  shows wildlife 2/5 with "No wildlife experiences are mentioned in the text" although the same page features the
  Sloth Adventure and Palo Verde tours. Needs a generator-level investigation; never hand-edit generated output.
- **Provenance:** the phrase "Wildlife/rainforest near LIR - not beach" has NO verified earlier record in the repo.
  Do not cite it as an existing candidate or as prior approval.
- **Evidence status:** GSC (2026-10-12) has no wildlife query mentioning Hermosa; "Google value" and "AI-answer value"
  ratings in the signal are unverified hypotheses.
- **DataForSEO:** none authorized or spent ($0.00). Any later research needs its own authorization, separate from
  Pilot V1. Production files, `blog-data.json`, generators and deployments untouched.
- **Deferred note, signal logged 2026-10-16 - alternatives beyond La Fortuna / destination choice:** a traveler asked
  where to go besides La Fortuna, Monteverde and Manuel Antonio. Recorded as a demand observation only, NOT a
  validated high-volume SEO opportunity: GSC (2026-10-12) has no "besides La Fortuna" / "hidden gems" style queries,
  and no measurement supports any AI-answer-value rating. "After La Fortuna: Monteverde, Bijagua or Guanacaste?" is a
  descriptive label only - it has no verified earlier record and is not a previously approved opportunity. Owners
  preserved: `/blog/which-day-trip-from-papagayo-fits-you` = ecosystem decision owner;
  `/blog/costa-rica-without-a-car-guide` = itinerary decision owner, subject to the `BLOG-COSTA-RICA-WITHOUT-CAR-001`
  Day 28 checkpoint (~2026-10-20; no edits before it). Candidate framing, unvalidated: choose the next destination by
  the ecosystem/experience the itinerary is missing, not by popularity (a pairing such as rainforest/wildlife ->
  Bijagua, volcanic -> Rincon, wetlands -> Palo Verde, beach by desired atmosphere must be checked against
  first-party tour records before any publication). Guardrails: respect the already-published Monteverde guidance
  (`is-monteverde-worth-a-day-trip-from-guanacaste`: day trip, not an overnight leg) and never imply commercial
  coverage Wild Papagayo does not have; the Bijagua birdwatching claim stays unpublished until the exact official ICT
  source is retrieved, read and verified. No new URL; no generic "places besides La Fortuna" page. DataForSEO $0.00.

## Honeymoon profile curation = DEPLOYED (deployed 2026-09-30)

Cloudflare deployment `05a54234` (https://05a54234.wild-papagayo.pages.dev). Verified live on
`https://wildpapagayo.com/profiles/honeymoon`. Deployed using the new one-baseline workflow (rebuilt
`current-baseline` → temporary package → overlay `profiles/honeymoon.html` only → deploy → validate → refresh
baseline from the exact deployed state → delete temporary package). Package diff: exactly 1 file
(`profiles/honeymoon.html`), 0 unexpected changes.

Live inventory confirmed exact: **hotels** — Borinquen Thermal Resort, Four Seasons Resort Costa Rica at
Peninsula Papagayo, Occidental Papagayo (unchanged, still matched via literal "Honeymoon(ers)" text in their
own `best_for`). **Tours (3 of 8 eligible)** — Oropendola Waterfall & Río Negro Hot Springs, Costa Rica
Highlights Tour, Sloth Adventure Tour Costa Rica. **Destinations (3 of 6 eligible destination files / 5
approved entries)** — Papagayo, Rincón de la Vieja, Río Celeste (chosen over Bijagua for the approved "Río
Celeste / Bijagua" line item — higher GSC traffic, stronger hero description). Canonical, title, H1, schema
unchanged. Order controlled by a new, honeymoon-scoped `preferred_tours`/`preferred_destinations` field on the
honeymoon object in `knowledge/traveler-profiles.json`, read by a small, backward-compatible addition to
`Get-TopMatches` in `experience-profile-generator.ps1` (no effect on any other profile — confirmed unchanged
before/after both locally and via live regression spot-check: homepage, llms.txt, both protected RIU transfer
pages, a blog article, a tour, a hotel, a destination, and `profiles/couples` all verified unaffected).

Eligibility remains broader than what renders: 8 tours and 6 destination files carry the `"Honeymooners"`
`best_for` tag (5 CORE + 3 OPTIONAL tours; 2 CORE + 3 OPTIONAL destination entries), but the generator's card
limit shows only 3 of each — this is the owner-approved curated subset, not a bug. Style grouping by experience
type (Nature & Wildlife / Waterfall / Hot Springs / Adventure / Relaxed-Scenic / Cultural-Coffee / Combination
Day) remains explicitly **DEFERRED** to a separate future task — not implemented. Anniversary/proposal remain
untouched, `SEPARATE_FUTURE_RESEARCH`. IndexNow: not called (no established project workflow for it on existing
pages). `current-baseline` refreshed from the exact deployed package (530 files — 2 fewer than the 532 count
recorded elsewhere, accounted for entirely by Wrangler's local `.wrangler/cache/` directory, not deployable site
content). Prior baseline state backed up to
`../wild-papagayo-deploy-history-archive/wild-papagayo-deploy-current-baseline-backup-pre-honeymoon-20260930`.
Full record: `seo-intelligence/reports/honeymoon-experience-product-curation-audit.md`,
`seo-intelligence/reports/honeymoon-anniversary-romantic-experiences-opportunity-analysis.md`, and
`seo-intelligence/reports/production-baseline-rebuild-2026-09-30.md`.

## Honeymoon profile curation = IMPLEMENTED LOCALLY, NOT DEPLOYED (2026-09-30) — superseded by deployment above

Owner approved 6 curation decisions (`seo-intelligence/reports/honeymoon-experience-product-curation-audit.md`).
Implemented: added a `"Honeymooners"` entry to the `best_for` array of 8 approved tours (Oropendola Waterfall &
Río Negro Hot Springs, Miravalles Volcano Waterfalls & Natural Spa, Costa Rica Highlights Tour, Rincón de la
Vieja Hiking Tour, Sloth Adventure Tour Costa Rica, Arenal Hanging Bridges Mistico, Monteverde Hanging Bridges &
Coffee Tour, Waterfall & Las Pumas Wildlife Rescue Center) and 6 destination files representing the 5 approved
destination entries (Papagayo, Rincón de la Vieja, La Fortuna, Monteverde, Bijagua, Río Celeste — Bijagua/Río
Celeste are two real files under one approved "Río Celeste / Bijagua" line item). No generator code change, no
numeric score, no couples alias — uses the generator's existing word-match fallback, the same mechanism that
already matched the 3 honeymoon hotels via literal "Honeymoon(ers)" text. Regenerated all 8 experience profiles
(`experience-profile-generator.ps1` has no per-profile mode); `profiles/honeymoon.html` changed as intended.
`profiles/couples.html` also changed, but not because of anything this task touched — its working-tree copy was
already stale relative to both current source data and live production (confirmed: the regenerated file's hash
matches `../wild-papagayo-deploy-current-baseline/profiles/couples.html` exactly, i.e. what's actually live).
Real, reportable limitation found: the generator's word-match fallback has no CORE/OPTIONAL tiering and takes
the first 3 matches in file-alphabetical order — rendered honeymoon tours are 2 CORE + 1 OPTIONAL (Arenal
Hanging Bridges, Costa Rica Highlights, Rincón de la Vieja Hiking), and rendered destinations are **0 CORE + 3
OPTIONAL** (Bijagua, La Fortuna & Arenal, Monteverde) — neither owner-approved CORE destination (Papagayo,
Rincón de la Vieja) currently renders. Not fixed in that task (would have required generator architecture
changes) — **resolved in a same-day follow-up task** (below).

**Follow-up: curated render priority = IMPLEMENTED LOCALLY, NOT DEPLOYED (2026-09-30, same day).** Added the
smallest possible honeymoon-specific mechanism rather than a broad generator refactor: an optional
`preferred_tours`/`preferred_destinations` array on the honeymoon object only in
`knowledge/traveler-profiles.json` (`["oropendolahotsprings","costaricahighlights","slothadventure"]` /
`["papagayo","rincon-de-la-vieja","rio-celeste"]`), and a small addition to `Get-TopMatches` in
`experience-profile-generator.ps1` that checks for this field (present only on honeymoon; every other profile
has no such field, so behaves exactly as before — confirmed via checksum, all 7 other profiles byte-identical
before/after). Preferred IDs are honored only if still eligible (tagged `Honeymooners`), with graceful fallback
to the normal score/word-match selection if fewer than 3 valid preferred entities exist. Result: honeymoon now
renders exactly the owner-approved order — hotels unchanged (Borinquen, Four Seasons, Occidental), tours
(Oropendola Waterfall & Río Negro Hot Springs, Costa Rica Highlights Tour, Sloth Adventure Tour Costa Rica),
destinations (Papagayo, Rincón de la Vieja, Río Celeste — Río Celeste chosen over Bijagua as the canonical card
for the approved "Río Celeste / Bijagua" line item: higher GSC traffic, 30 vs 6 impressions, and the stronger
first-party hero description). Eligibility unchanged (8 tours / 6 destination files still tagged; only 3 of
each render, by design). Style-grouping by experience type remains explicitly deferred to a separate future
task. Validators: 25 pre-existing unrelated errors, 0 new. Canonical/title/schema unchanged. Not deployed. Full
record: `seo-intelligence/reports/honeymoon-experience-product-curation-audit.md` (implementation section) and
`seo-intelligence/reports/honeymoon-anniversary-romantic-experiences-opportunity-analysis.md`.

## Honeymoon / anniversary / romantic experiences research = EXPAND_EXISTING (research only, 2026-09-30)

A business-development question (honeymoon/anniversary/romantic private-experience opportunity, also evaluated
for "The Romantic Tourist" marketplace fit) was researched, not implemented. **Key finding: a live page already
exists** at `profiles/honeymoon.html` (+ sibling `profiles/couples.html`), both generated from
`knowledge/traveler-profiles.json` via `experience-profile-generator.ps1`. The honeymoon page already
recommends 3 real hotels (incl. the confirmed adults-only Occidental Papagayo) but has zero matched tours/
destinations ("coming soon") due to a specific, identified one-line gap in the generator's
`$scoreKeyAliases` map (only `adventure` has an alias; `honeymoon` has no alias to the already-populated
`couples` scoring dimension tours/destinations actually carry). GSC shows thin, unranked evidence (`gulf of
papagayo honeymoon resorts`, 3 impressions; the page itself, 1 impression) — real but not enough alone to
justify a new URL. `destinations/papagayo.html` also already claims "Ideal for honeymoons, anniversaries and
private travel" in its `highlights`. No DataForSEO connector was available this session (tool search found
none) — not a cost-cap decision. Decision: `EXPAND_EXISTING`, not `NEW_LANDING` — complete the page that
already exists rather than build a new one. Not implemented (research-only task). Full record:
`seo-intelligence/reports/honeymoon-anniversary-romantic-experiences-opportunity-analysis.md`.

## Flamingo all-inclusive / milestone-celebration signal = DEFER / NEEDS_FIRST_PARTY_HOTEL_EVIDENCE (2026-09-29, corrected same day)

A Facebook traveler question about Flamingo + all-inclusive + adults/couples milestone celebration was audited
and **deferred** — DEFER stands after a same-day correction. **Correction:** the audit initially checked the
wrong source (`knowledge/hotels.json`, a stale legacy file — now flagged in `CLAUDE.md`) and wrongly concluded
zero footprint near Flamingo. Corrected: `transport.js` has a live, priced `FLAMINGO_CONCHAL` transfer zone, and
`knowledge/hotels/` (the real runtime source) has a real hotel profile for The Westin Reserva Conchal
(all-inclusive, but generic/undifferentiated scores, `status: draft`). DEFER still stands because no property in
Flamingo, Conchal, or Matapalo carries a confirmed **adults-only or differentiated couples/milestone**
classification — the one property that does, Hotel Occidental Papagayo (`category: "Adults-Only All-Inclusive
Beach Resort"`, couples score 5/5), is in Papagayo, a different area. No content was produced. GSC shows no
Flamingo+all-inclusive query, but does show real (low-volume, unranked) impressions for `all inclusive resorts
in papagayo costa rica`, `papagayo all inclusive resorts`, `andaz papagayo all inclusive`, and `riu palace costa
rica adults only` — a **related but distinct** intent, logged as `SEPARATE_FUTURE_OPPORTUNITY` (not started,
Occidental Papagayo's confirmed adults-only profile is a concrete lead for whenever that audit happens) rather
than substituted for the Flamingo signal. No new URL, no new section, no Papagayo content modified, no
DataForSEO calls. Full record, including the full evidence-provenance correction:
`seo-intelligence/reports/flamingo-all-inclusive-milestone-opportunity-analysis.md`.

## GREEN-SEASON-VERANILLO-001 = DEPLOYED / OBSERVATION READY (deployed 2026-09-29)

Cloudflare deployment `bee439ed` (https://bee439ed.wild-papagayo.pages.dev, branch `main`). Verified live on
`https://wildpapagayo.com` (custom domain, not just the `.pages.dev` URL). Full detail, exact copy, and the
critical baseline finding below: `seo-intelligence/reports/guanacaste-green-season-veranillo-opportunity-analysis.md`
("Implementation record" + "Deployment record" sections).

Three owner-approved actions: (1) a new "Green Season Isn't One Thing" section, incl. the IMN-sourced Veranillo
de San Juan explainer (~60% occurrence last two weeks of June, ~15% chance of a strong/7+-day event, Pacific
North region), appended to `content_block_2` of `costa-rica-in-september-will-rain-ruin-your-tours` (title/URL/
FAQ schema unchanged); (2) one internal-link addition (no restated content) from
`playa-hermosa-guanacaste-with-kids` to that article; (3) a `month-generator.ps1` source correction moving the
veranillo mention from July to June, wording softened to "Late June **can** bring..." per final owner review.
None of the five active experiments reference any of the touched files. Deployed files: the two blog articles,
`months/june.html`, `months/july.html`, `sitemap.xml` (lastmod bumped for exactly those 4 URLs, `2026-09-29`).
Validators: content-link-validator 25 pre-existing unrelated errors (0 new); knowledge-validator 46 pre-existing
unrelated errors (0 new). IndexNow: not called. Backup:
`knowledge/backups/blog-data/blog-data-20260929-195440.json`.

**RESOLVED 2026-09-29 (same day, separate authorized repair task):** `../wild-papagayo-deploy-current-baseline`
was found STALE during this deploy (predated the 2026-09-26 footer change) and has since been **repaired**. Full
forensic record, verification method and manifest:
`seo-intelligence/reports/deploy-baseline-repair-2026-09-29.md`. Summary: root cause was a broken manual-refresh
habit at the `BOOKING-POLICY-72H-001` fork point (2026-09-26), never automated by any script (confirmed — no
`.ps1` file references this folder). Stale copy preserved at
`../wild-papagayo-deploy-current-baseline-backup-20260929-205126` (532 files, untouched). `current-baseline` was
replaced with a copy of `../wild-papagayo-deploy-green-season-001` (the exact `bee439ed` deploy package),
verified two ways: (1) SHA-256 checksums of all 532 files, 0 mismatches; (2) 10 diverse live pages (home,
`/transport`, both RIU transfer pages, `llms.txt`, both legal pages, a blog article, a hotel page, a tour page)
fetched fresh from `wildpapagayo.com` and diffed against it directly — the only remaining differences on any
page were the documented Cloudflare email-obfuscation/analytics injections. `current-baseline` is now current
through deployment `bee439ed`.

**Standing rule going forward:** `current-baseline` (or any similarly-named folder) is a **point-in-time
verified snapshot, never a permanent guarantee**. Before building a deploy package from it, check its recorded
deployment ID/date (this note) against the latest entry in this file's deployment history; if a newer deployment
exists that it doesn't cover, refresh it first, the same way this repair did, before building the next scoped
package. See also `CLAUDE.md`'s "Deployment safety rules" for the permanent version of this rule.

## PACKING-WITH-KIDS-DEPLOY-001 = DEPLOYED (deployed 2026-09-29)

Cloudflare deployment `156658d8` (https://156658d8.wild-papagayo.pages.dev, branch `main`). Verified live on
`https://wildpapagayo.com`. Full detail: `seo-intelligence/reports/green-season-packing-kids-opportunity-analysis.md`
("Deployment record" section).

Owner-approved "Packing With Kids in Green Season" section appended to `content_block_2` of
`green-season-packing-list-guanacaste-arenal` (existing owner, no new URL, title/canonical/FAQ schema unchanged).
Same-day final micro-fix applied before deploy: the insect-protection bullet's "Arenal's greener, wetter terrain
tends to have more insect activity than the coast" comparison was removed, replaced with "especially useful for
rainforest and nature activities." Deployed files: the one blog article and `sitemap.xml` (lastmod bumped for
exactly that 1 URL, `2026-09-29`). Validators: content-link-validator 25 pre-existing unrelated errors (0 new).
IndexNow: not called.

This was the first deploy since the same-day `current-baseline` repair (`GREEN-SEASON-VERANILLO-001` entry
above). Pre-deploy baseline gate passed (live production confirmed to not yet contain the new section, proving
`current-baseline`'s claimed `bee439ed` state was still current). Post-deploy, `current-baseline` was refreshed
again — prior state backed up to `../wild-papagayo-deploy-current-baseline-backup-20260929-packing-kids-pre`,
replaced with the deployed package, verified via `diff -rq` + SHA-256 of all 532 files (0 mismatches).
`current-baseline` is now current through deployment `156658d8`. Full manifest update in
`seo-intelligence/reports/deploy-baseline-repair-2026-09-29.md`.

Note: the working-tree `sitemap.xml` again could not be shipped wholesale (unrelated pre-existing `lastmod`
drift, same recurring issue as the Green Season deploy) — the single approved line was instead applied directly
to the baseline's own sitemap copy.

## Current workstream: ENTITY-TRANSFER-002 (LIVE, verified 2026-09-20)

New private-transfer landing `/transfers/liberia-airport-to-la-fortuna` (LIR <-> La Fortuna & Arenal, both
directions, quote-only pricing, no night arrivals). Deployed as Cloudflare deployment f034d944 (7 files) and verified live.
Observation clock started 2026-09-20 18:10 -0600. No IndexNow, no indexing request yet (user has not asked).

- Source: `knowledge/landing-pages/liberia-airport-to-la-fortuna.json`. `landing-page-generator.ps1` gained two
  opt-in features (`webpage_id`, `content_blocks` + `CONTENT_BLOCK:name` in `section_order`); they render nothing
  for pages that do not declare them. The two Riu transfer pages and all 8 private-tours pages stayed byte-identical.
- Inbound links: one `internal_links` entry on 3 articles in `blog-data.json`
  (LIR transfer guide, LIR-to-Arenal drive times, La Fortuna without a rental car).
- `transport.html`: 3 small insertions (Popular routes link; the "day or night" card now says LIR -> La Fortuna is not offered for
  night arrivals; estimator intro says amounts are estimates, not guaranteed fixed rates). `transport.js` untouched.
- `llms.txt`: +1 line under Airport Transfers. `sitemap.xml`: +1 URL, `lastmod` bumped only for the 4 changed pages.
- Experiment record: `seo-intelligence/experiments/ENTITY-TRANSFER-002.json` (facts used, baseline, measurement plan).
- Prepared package: `../wild-papagayo-deploy-et002` = verified baseline + exactly 7 public files
  (`transfers/liberia-airport-to-la-fortuna.html`, 3 blog articles, `transport.html`, `llms.txt`, `sitemap.xml`).
  Deployed from that folder; `../wild-papagayo-deploy-current-baseline` was refreshed with those 7 files so it again equals live.

## Live state (from this session's deploys)

Live on wildpapagayo.com: ENTITY-TRANSFER-002 (LIR <-> La Fortuna landing), clean-URL migration, CRO pilot (Andaz, Costa Rica Highlights), FC-001/002/003 fixes,
Blog P1 (Rincon, Riu rental car incl. FAQ fix, Monteverde). `../wild-papagayo-deploy-current-baseline` equals live
(Cloudflare email obfuscation reversed). The previous version of this file called Monteverde undeployed; that was stale.

## Owner-confirmed facts for the new route (do not contradict)

- Quote-only pricing: never publish $310/$370/$500 or Offer/priceRange for this route.
- Booking/cancellation (superseded 2026-09-26, see `BOOKING-POLICY-72H-001`): 25% deposit, balance due 72 hours before pickup, full payment for bookings within 72 hours, cancellations within 72 hours non-refundable subject to mandatory consumer rights. (Old rule was "cancel free with 24+ hours' notice".) Flight delays: first 60 minutes of waiting free (unchanged).
- Not offered for flights arriving at night; no fixed advance-booking lead time; no vehicle/passenger assignments.

## Open items (reported, not fixed)

- `transport.js` still shows $310/$370/$500 for LIR <-> La Fortuna (labelled as estimates on /transport now);
  Terminosycondiciones FAQ "72+ hours" is generic and conflicts with tour and transfer policy (separate policy task).
- `assistant-knowledge-validator.ps1` fails on 2 Riu checks (expects `.html` URLs, stale after FC-003);
  `knowledge-validator.ps1` reports 45 unrelated graph errors; `content-link-validator.ps1` does not scan `transfers/`.
- `functions/assistant-knowledge.json` was not regenerated (new page would get empty origin/destination/travel_time): follow-up architecture issue.
- Andaz CRO hero exists only in the synced `knowledge/hotels` layer; never run `hotel-legacy-publish-all.ps1`.
- Tamarindo-surround Coaster price anomaly ($530 vs $610) in `transport.js`; stale Andaz wording and a hardcoded
  "Guanacaste and Arenal" claim in `llms.txt` generator (deferred).
- `rss.xml` gives undated items the build time as `pubDate`, so two items change on every blog regeneration
  (restore from baseline instead of shipping the churn).
- `recommendation-engine.ps1` and `recommendation-validator.ps1` are byte-identical (validator may validate nothing).

## Must not be reverted

- Clean-URL link changes, `_redirects`, CRO pilot blocks, the Blog P1/Monteverde edits in `blog-data.json`,
  `index.html` title/meta changes, `.gitignore` additions, `knowledge/backups/`, every untracked file.
- ENTITY-TRANSFER-001 and BLOG-URL-NORMALIZATION-001 stay as they are (their clocks are running).

## MULTIGEN-FAMILY-SECTION-001 = DEPLOYED (deployed 2026-09-29)

Cloudflare deployment `861d795c` (https://861d795c.wild-papagayo.pages.dev, branch `main`). Verified live on
`https://wildpapagayo.com`. Full detail:
`seo-intelligence/reports/multigenerational-large-family-opportunity-analysis.md` ("Deployment record" section).

Owner-approved "Traveling With a Multigenerational or Large Family" section appended to `content_block_3` of
`playa-hermosa-guanacaste-with-kids` (existing owner, no new URL). Uses only activities already established in
the article's own age table (Palo Verde River Boat, Las Pumas, Rincón de la Vieja, Celeste hike, beach/rest day).
No vehicle/luggage capacity numbers invented (no such fact exists in `knowledge/transportation.json`); logistics
kept request-based. Manuel Antonio excluded per the operating-area honesty rule. Two editorial corrections
applied per owner review before implementation: removed a "less mobile grandparents" framing (replaced with
neutral "family members looking for a gentler day"), and made rest-day language optional ("can," "may," "for
some families") rather than prescriptive.

Deployed file: only the one blog article. **Same-day sitemap exception:** the target URL's `lastmod` was already
`2026-09-29` in the verified baseline (set by the earlier Green Season deploy's internal-link addition to this
same article); since this project's sitemap lastmod is date-only, there was no distinct newer value to write, so
`sitemap.xml` was intentionally left untouched rather than shipped as a no-op edit — owner-approved exception,
`PACKAGE_DIFF_FILE_COUNT = 1` (expected, not a warning). Validators: content-link-validator 25 pre-existing
unrelated errors (0 new). Canonical, FAQ, schema, and internal_links unchanged. IndexNow: not called.

This was the second deploy since the baseline repair. Pre-deploy baseline gate passed (live production confirmed
still at `156658d8`). Post-deploy, `current-baseline` was refreshed again — prior state backed up to
`../wild-papagayo-deploy-current-baseline-backup-20260929-multigen-pre`, replaced with the deployed package,
verified via `diff -rq` + SHA-256 of all 532 files (0 mismatches). `current-baseline` is now current through
deployment `861d795c`. Full manifest update in `seo-intelligence/reports/deploy-baseline-repair-2026-09-29.md`.

## Deploy method (only when the user explicitly approves)

Build from the verified baseline plus the exact file overlay, gate with `diff -rq`, then from the repo's parent folder run
`npx wrangler pages deploy "<package dir>" --project-name wild-papagayo --branch main`. Never use `deploy-package.ps1`
(regenerates everything and runs IndexNow). Compare live to local with `curl`, not python urllib (403).
Do not commit, reset, clean, stash, deploy, or publish unless explicitly authorized. Snapshot/scratch folders next
to the repo are not to be edited.

## Production baseline rebuild + deploy-folder consolidation (2026-09-30)

**Finding:** a forensic audit found `../wild-papagayo-deploy-current-baseline` was NOT a reliable full mirror of
production — the scoped-overlay deploy method (copy baseline + overlay 1-2 approved files, repeat) never
re-synced anything outside each task's narrow overlay, so unrelated pages could silently drift. Two real,
separate mechanisms were found: (1) `blog-data.json` had grown from 38 to 57 articles in the working tree
without ever being part of any deploy package (it's a source file, never overlaid), causing blog pages and their
"Travel Insights" cross-link sections on tour/hotel pages to differ from a naive comparison; (2) raw byte-size
comparisons against live were themselves contaminated by *unnormalized* Cloudflare edge injections (email
obfuscation, the Cloudflare Web Analytics beacon script), making live pages look bigger/different than they
really were. Once properly normalized, the **old baseline actually matched live production on 176 of 177
sitemap-covered pages** — the real production risk was much smaller than the raw byte-diff count (93 files)
suggested.

**Fix:** rebuilt `current-baseline` directly from verified live production (not from any prior folder, not from
the working tree). Method: fetched all 177 live URLs (175 from `sitemap.xml` + `Bookingform`, `single-blog`),
decoded/stripped 4 Cloudflare edge transformations (see below), wrote the normalized result into a candidate
built from the old baseline's file structure (preserving all 355 non-HTML/CSS/JS/image/font files, spot-verified
unchanged: `style.min.css`, `script.js`, `tour-pricing.json`, `transport.js` all byte-identical live vs. old
baseline), then verified the candidate against a second, independent fresh live re-fetch across 13 diverse
pages (both protected RIU transfer pages, `profiles/honeymoon`, `llms.txt`, `sitemap.xml`, `index.html`, a blog
article, a tour, a hotel, a destination, a category, a month) — all EXACT. `MATERIAL_MISMATCHES = 0`.
`destinations/playa-conchal.html` (draft, live 404) correctly excluded. `profiles/honeymoon.html` in the new
baseline correctly reflects the CURRENT LIVE state (no curated tours yet) — the pending local Honeymoon work
was NOT included, since the baseline represents production, not pending work.

**Edge normalization rules applied** (documented so future comparisons don't re-flag these as real drift):
1. `<span class="__cf_email__" data-cfemail="HEX">[email&#160;protected]</span>` → decoded (simple XOR cipher,
   first byte is the key) back to the plain email text.
2. `href="/cdn-cgi/l/email-protection#HEX"` → decoded back to `href="mailto:<email>"`.
3. Injected `<script data-cfasync="false" src="/cdn-cgi/scripts/.../email-decode.min.js"></script>` → removed.
4. Injected Cloudflare Web Analytics beacon (`<script type="module" src="https://static.cloudflareinsights.com/
   beacon.min.js/..." ... data-cf-beacon='...'></script>`) → removed. (Previously undocumented — this site does
   run Web Analytics, contrary to an earlier assumption that it didn't.)
One additional benign, newly-observed Cloudflare behavior: occasional inline whitespace/line-break collapsing
inside HTML attributes (found on `contact.html`, purely cosmetic, zero content change) — not systematically
normalized, but confirmed non-material wherever seen.

Old baseline preserved (not deleted) at `../wild-papagayo-deploy-history-archive/wild-papagayo-deploy-current-baseline-backup-OLD_INCOMPLETE_BASELINE_PRE_RECONCILIATION-20260930`.

**Deploy-folder consolidation:** 25 historical `wild-papagayo-deploy-*` folders (task-named one-off packages
going back through this project's history, e.g. `favicon-fix`, `home-h1-001`, `destbubu-001`, `et002`, plus
3 dated baseline backups) plus one stray `.zip` were moved intact (not deleted, not compressed — ~1.4GB of
mostly-redundant static snapshots made a zip impractically slow) into
`../wild-papagayo-deploy-history-archive/`. The active parent folder now holds exactly two items:
`wild-papagayo-deploy-current-baseline` (the one live baseline) and `wild-papagayo-deploy-history-archive` (the
archive, not a deploy source).

```
CURRENT_BASELINE_SOURCE = LIVE_PRODUCTION_RECONSTRUCTION
CURRENT_BASELINE_PRODUCTION_ID = 861d795c
SAFE_FOR_FUTURE_DEPLOY_BASE = YES
ACTIVE_DEPLOY_BASELINES_REMAINING = 1
HONEYMOON_STATUS = APPROVED_LOCAL_PENDING_DEPLOY (unchanged by this task)
```

**Standing rule going forward — ONE VERIFIED BASELINE MODEL:** for every future deploy: (1) verify production
hasn't changed; (2) copy `current-baseline` to a *temporary* package directory; (3) overlay only the approved
production-facing files; (4) inspect the exact delta; (5) deploy that directory (never a zip); (6) validate
production; (7) only after successful validation, refresh `current-baseline` from the exact deployed
state; (8) remove the temporary package; (9) never create another permanent task-named deploy folder — if one
is created for a specific deploy, it is temporary and gets deleted or folded back into step 7, not kept. Also:
**the source working tree is not the production baseline** — they serve different purposes and will legitimately
diverge (pending/local work vs. what's actually live); don't assume one reflects the other without checking.

## Last handoff

- Date: 2026-10-03. Work: TOUR-POLICY-CENTRALIZATION-001 — booking/cancellation policy for all 33 active tours
  centralized into one source of truth, `knowledge/policies/booking-cancellation.json` (version 1: holds
  `reservation_policy_core`, `reservation_policy_noshow`, and `cancellation_faq` {question, answer}), replacing
  the 33 independent `page_content.accordion.reservation_policy` copies that previously lived inside each
  `knowledge/tours/<slug>.json`. `tour-generator.ps1` now loads this file once, fails the whole build if it is
  missing or any required field is empty, and composes each tour's Reservation Policy accordion as
  `[core, noshow (unless the tour sets reservation_policy_include_noshow: false), ...tour-specific
  reservation_policy_extra]` — the no-show paragraph and the tour-specific weather/rescheduling/park-registration
  riders were NOT force-unified (laleona and tubingceleste genuinely omit the no-show clause today; weather
  wording legitimately differs by activity — forcing one wording onto all 33 would have been a content change,
  not a refactor). The one shared cancellation FAQ (25 of 33 tours have "Can I cancel my reservation?") is
  resolved the same way via `answer_source: "central_policy:cancellation_faq"` on the FAQ item, read by the
  same generator function (`Get-FaqAnswer`) that builds both the visible accordion/FAQ HTML and the FAQPage
  JSON-LD from one in-memory value, so they cannot drift. `tour-knowledge-validator.ps1` gained two regression
  guards: the central file must exist with all required fields, and no tour may reintroduce a hard-coded
  `page_content.accordion.reservation_policy` or any of the retired policy's wording ("48 hours", "7 days",
  "50% refund", etc.). Verified byte-for-byte: regenerating all 33 tour pages + `tours.html` after the
  centralization produced IDENTICAL output to before it (sha256 over all 34 files, zero diffs) — this was a
  pure source-of-truth refactor with no visible or schema change. To change the policy in the future: edit the
  three fields in `knowledge/policies/booking-cancellation.json`, bump `version`, then run
  `tour-generator.ps1` — never hand-edit the wording back into an individual tour's JSON. Not committed, not
  deployed, no IndexNow.
- Date: 2026-09-22/23. Work: BLOG-COSTA-RICA-WITHOUT-CAR-001 deployed and verified (3dac2c33) — 55th blog
  article, full research-through-deploy pipeline ($0.06 total external cost); LIR-corridor-scoped no-car guide
  covering 4 transport modes with transparent solo economics; hero is a real owner photo with the front license
  plate pixelated (conventional, non-generative edit) after visually confirming it against two explicitly
  excluded alternate photos; deferred child `7_10_DAY_WILDLIFE_NO_CAR_ITINERARY` not built this session;
  observation clock started, checkpoints Day 7/14/28; earlier: BLOG-PLAYA-HERMOSA-FAMILY-001 deployed and verified (8f3edad9) — 54th blog article,
  full research-through-deploy pipeline ($0.06 total external cost); an AI-generated hero image was caught and
  rejected mid-workflow before the real owner camera photo (DSC01450.JPG, EXIF-verified Sony DSC-W530, 2012) was
  used instead; new source-of-truth debt recorded: Palo Verde River Boat age (source 8 vs owner-confirmed 2,
  likely resolves the long-standing River Boat minimum-age question), Congo Trail age (source 0 vs
  owner-confirmed 4), and a likely stock-photo (fam.1.webp) on the Playa Hermosa destination page's own hero,
  flagged not fixed; earlier: BLOG-ARRIVAL-DAY-PAPAGAYO-001 deployed and verified (1b35a0b0) — 53rd blog article,
  hero is a real user-provided photo accepted at native 669×446 resolution (smaller than usual, explicitly
  approved by the user); airport→tour→hotel explicitly confirmed and written as NOT a standard workflow,
  deliberately avoiding false symmetry with Departure-Day's separate custom tour→airport option;
  BLOG-DRY-SEASON-IN-GUANACASTE-001 deployed and verified (9ea83715) — 52nd blog article,
  hero is an explicit user-approved content reuse of guanacaste-hero.webp under a new filename; Four Seasons
  "December to August" best_season outlier remains a separate, unresolved data-cleanup note; BLOG-CAN-YOU-DO-A-TOUR-ON-DEPARTURE-DAY-001 deployed and verified (ec0ea50e) — 51st blog
  article, hero required a user-confirmed Papagayo-geography exception after an initial porte-cochere-architecture
  flag; HUB-CANYON-CONGO-LINK-001 deployed and verified (f078f7d2) — one-file inbound-link patch, Canyon Adventure Park age conflict (8 vs 5) still unresolved and deliberately not surfaced; BLOG-PAPAGAYO-DAY-TRIP-HUB-001 deployed and verified (c836acee) — closes the comparison-cluster arc, favor this hub/pairwise/deep-dive hierarchy over new pairwise comparisons going forward; BLOG-RIO-CELESTE-VS-RINCON-001 deployed and verified (b72b449c); BLOG-PALO-VERDE-VS-RINCON-001 deployed and verified (569b2c7a); LLMS-LA-FORTUNA-BACKFILL-001 deployed and verified (932b9b9b); BLOG-PAPAGAYO-TRANSPORTATION-001 deployed and verified (e8312ad3); earlier: BLOG-LA-FORTUNA-DURATION-001 deployed and verified (a353cd8c); Secrets Papagayo article (0c889a0a); Half-Day article (95f506c5); Palo Verde article (5c8ab614); Waldorf article (9fed6168); Nekajui article (6fe752ae); Riu Palace article (63a175d6); Ostional P1 deployed and verified (bc164cd6); ET-002 and BLOG-BABY-NO-CAR-001 live; transfer-navigation audit (research only, Phase 1 NOT started); Palo Verde ops questions (River Boat minimum age, El Viejo boat privacy, El Viejo tide dependence) remain genuinely unresolved from local evidence, unchanged. No commit, IndexNow or indexing request.
- On resume: read both files, then confirm the working tree matches this note before acting.
