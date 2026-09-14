# ID Verification Data Sources and Implementation Plan

## Bottom Line
Building and maintaining rules for all IDs globally by hand is not a reliable or efficient strategy.
Use a production KYC/IDV provider for primary verification, and keep local OCR parsing only as a fallback UX helper.

## Recommended Primary Path (Production)
Use one provider that already maintains country/state ID templates and anti-fraud checks:
- Persona
- Onfido (Entrust)
- Veriff
- Sumsub
- Stripe Identity

What this gives immediately:
- Country/state document-type coverage updates managed by provider
- Template + OCR + fraud checks (hologram/security checks where available)
- Liveness/selfie matching flows
- Sanctions/PEP options if needed
- Audit trail for compliance

## Authoritative Standards/Data to Anchor Internal Logic
These are the standards your internal fallback should map to:

1. Passport + MRZ (global)
- ICAO Doc 9303 (Machine Readable Travel Documents)
- Core utility: deterministic extraction of names, document number, nationality, DOB, expiry from MRZ

2. Country + subdivision normalization
- ISO 3166-1 (country codes)
- ISO 3166-2 (subdivision/state/province codes)
- Source reference: ISO 3166 maintenance agency and OBP data feed

3. US/Canada driver license ecosystem
- AAMVA card/barcode specifications (jurisdiction-level implementation)
- Core utility: parse PDF417 payload where present instead of only visual OCR

4. eID/mDL direction
- ISO/IEC 18013-5 (mobile driving licence) for future digital ID flows

## Anti-Fraud Signals to Add Immediately (Research-Backed)
1. MRZ structural integrity (ICAO Doc 9303)
- Validate expected MRZ line lengths and allowed character set (A-Z, 0-9, <)
- Validate MRZ check digits using 7-3-1 weighting
- Any checksum mismatch should force very low confidence and hard reject

2. Document consistency checks
- If parser route says passport MRZ but MRZ lines are missing/broken, hard reject
- If parser route says driver license but core fields (DOB/expiry) are missing, lower confidence or reject

3. Explicit novelty/specimen language blocks
- Reject when text includes: novelty, specimen, replica, fictitious, not valid for identification, or similar disclaimers

4. Synthetic pattern detection
- Flag obviously synthetic numeric sequences (e.g. repeated digits, ascending/descending runs)
- Combine with other signals for strict rejection

5. Placeholder identity signals
- Hard penalize placeholder names (John Doe, Jane Doe, Test Test) and first=last anomalies

## Internet Sources Used in This Iteration
- ICAO MRZ format and checksum behavior summarized from machine-readable passport references and Doc 9303-linked material
- AAMVA DL/ID standards overview confirming standards-driven anti-fraud posture and interoperable machine-readable fields

## Data Model You Need Internally
Create a verifier profile per document family:
- doc_family: passport_mrz | us_dl_pdf417 | national_id_generic | residence_permit
- country_iso2
- subdivision_code (optional)
- name_order_hint: family_given | given_family
- supports_mrz: bool
- supports_barcode: bool
- first_name_labels: [string]
- last_name_labels: [string]
- full_name_labels: [string]
- numeric_field_hints: [{field: "1", meaning: "family"}, {field: "2", meaning: "given"}]
- hard_exclude_tokens: [string] // state, address, class, restriction, etc.
- confidence_threshold

## Extraction Strategy (Deterministic Priority)
Always run in this order:
1. Structured zones first (MRZ, PDF417)
2. Explicit labeled fields (surname/first name variants)
3. Numbered field conventions (1=family, 2=given where applicable)
4. Generic full-name fallback with country name-order hint

Then apply:
- Middle-name policy: keep first given name as firstName; preserve family tokens in lastName
- Normalization: diacritics-insensitive matching, title-case output, joiner preservation (de, van, bin, etc.)
- Confidence scoring per extraction route

## What to Store from Verification Result
Store only what is needed:
- verified_first_name
- verified_last_name
- verified_display_name
- country_iso2
- document_type
- provider_verification_id (or local verification hash)
- verified_at timestamp
- confidence_score

Do not store raw ID images longer than required by policy.

## Privacy, Legal, and Security Requirements
- Explicit user consent before capture and processing
- Data retention policy (short TTL for raw media)
- Encryption at rest + in transit
- Access controls + audit logs
- Deletion workflow for user data requests
- Regional compliance review (GDPR/CCPA and local rules)

## Immediate Engineering Next Steps
1. Add provider SDK backend integration for primary verification
2. Keep current local OCR parser as fallback-only
3. Add extraction confidence score and reject low-confidence name outputs
4. Add test corpus by document family and country
5. Add telemetry: extraction route used, confidence, failure reason

## Practical Scope Recommendation
Phase 1 (fast + reliable):
- Provider integration + your current UI
- Username from verified firstName + lastName (already updated)

Phase 2 (coverage hardening):
- MRZ parser for passports
- PDF417 parser for US/Canada DL where barcode is captured
- Country-specific fallback profiles for top traffic countries

## Country Priority Memory (Who To Support First)
Prioritize countries with high smartphone penetration, high app usage, and large likely user pools.

Tier 1: Highest priority now
- US, CA, GB, DE, FR, ES, IT, NL, SE, NO, DK, FI, IE, CH, AU, NZ, JP, KR, SG, PT, BE, AT, LU

Tier 2: Next wave
- PL, CZ, RO, HU, GR, SK, SI, HR, BG, EE, LV, LT, CY, MT, IN, BR, MX, MY, PH, TH, ZA, TR, IL, ID

Tier 3: Long tail
- Remaining countries after telemetry confirms demand and false-reject rates

Implementation notes:
- Keep tier lists in code for immediate scoring/routing behavior.
- Add per-country parser label packs as telemetry identifies error hotspots.
- Any unsupported country should still process via generic route, but with conservative confidence.
