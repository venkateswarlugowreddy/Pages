# Technical Design Document
**Configuration of HOD Discount Authorization in Salesforce & DER Sanity Checks**

Demand Ref: MID OFFICE/2026/38020 | Source: HOD Discount Authorization & DER Sanity Checks – BRD, v1.3 (Final), 02 Jul 2026 | Platform: Salesforce

---

## 1. Introduction

This document provides detailed instructions and guidelines for developing the DER (Deal Exception Request) hygiene checks and the HOD (Head of Department) Discount Authorization Matrix in Salesforce. The purpose of this implementation is twofold: first, to ensure that a DER cannot be submitted unless the identity, agency, comment, and payment-plan data recorded on it is valid; and second, to automatically approve a DER against a configurable, date-bound authorization matrix wherever it falls fully within an active rule, so that only exceptions genuinely requiring human judgement reach the MIS team.

## 2. Prerequisites

### a. Custom Objects — HOD Discount Authorization Matrix

**Object 1: `DER_Authorization__c`**

Fields:
1. Start Date (Date)
2. End Date (Date)
3. Active (Formula)
4. Total Discount (Number) – Sum of DLD Waiver + Rebate + Price Discount.
5. HOD Authorization fields *(subject to confirmation — see Open Items, Section 4.1)*: HOD__c (Lookup to User), Token Exception % (Percent), and Token Exception Days (Number).

**Object 2: `DER_Authorization_Rule__c`**

Fields:
1. Deal Type (Multi-Select Picklist)
2. Country (Multi-Select Picklist)
3. Construction Status (Multi-Select Picklist)
4. Type of Inventory (Multi-Select Picklist)
5. Bedroom Type Exclusions (Multi-Select Picklist)
6. Building Code (Multi-Select Picklist)
7. Min Price (Decimal)
8. Max Price (Decimal)

### b. New Fields on DER

1. Agency Type (Formula) – Derived from the Agency Account's Record Type. Where the Agency field is blank, the value shall default to "Direct".
2. OCR Capture Fields (new, read-only): OCR Passport Number, OCR Passport Name, and OCR Nationality.
3. DP Hold Needed For (Picklist) – Values: 15, 30, 45, 60, 75, 90 (days).
4. RM Selected Info (Long Text) – Summarizes the selection information on a unit-wise basis.

## 3. Defining the Process

1. A new tab shall be provided to Business (Deepesh) for creating DER Authorization and DER Authorization Rule records, including their Start and End Dates.
2. A Building Code, together with its associated key parameters, shall not be active on more than one DER Authorization record at the same time.
   > Example: If DERA-001 is active from Date X to Date Y, with Building Code "DDA" and Bedroom Type "Studio", the resulting key is DDA#Studio. The same key shall not be permitted on another active record — for example, DERA-002 — for an overlapping period.
3. The Max Authority % and Token Exception fields shall be made mandatory. (The three HOD names shall be configurable.)
4. The OCR API integration shall be migrated from Azure to RPM. *(Please confirm the target platform name — see Open Items, Section 4.2.)*
5. The system shall validate whether the uploaded document is a passport or a national ID (for Iraq projects); documents of any other type shall not be permitted.
6. The RM shall have the option to amend the captured information. The OCR-extracted information and the amended information shall both be validated prior to submission; where the two do not match, submission shall not be permitted.
7. A new section shall be added to capture the DP (Down Payment) information.
8. Where the RM selects a value for "DP Hold Needed For", an option shall be provided to enter the corresponding payment-days schedule.
9. For Iraq projects, the National ID copy shall be mandatory and the passport copy shall be optional. For all other projects, only the passport shall be uploaded, and it shall be mandatory.
10. Once submitted, the RM Selected Info shall be summarized on a unit-wise basis and updated on the DER's "RM Selected Info" field.

## 4. Open Items for Confirmation

1. **Section 2(a), Object 1, Field 5:** Please confirm whether three parallel sets of HOD fields (HOD, Token Exception %, Token Exception Days) should be created directly on `DER_Authorization__c` — one set per HOD — or whether a related child object would be more appropriate, given that the number of HODs is fixed at three today but may change in future.
2. **Section 3, Item 4:** Please confirm the target platform name for the OCR API migration ("RPM").
