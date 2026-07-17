# Technical Design Document
**Configuration of HOD Discount Authorisation in Salesforce & DER Sanity Checks**

Demand Ref: MID OFFICE/2026/38020 | Source: HOD Discount Authorisation & DER Sanity Checks – BRD, v1.3 (Final), 02 Jul 2026 | Platform: Salesforce

---

## 1. Introduction

This document provides detailed instructions and guidelines for developing the DER (Deal Exception Request) hygiene checks and the HOD (Head of Department) Discount Authorisation Matrix in Salesforce. The purpose of this implementation is twofold: first, to ensure that a DER cannot be submitted unless the identity, agency, comment, and payment-plan data recorded on it is valid; and second, to automatically approve a DER against a configurable, date-bound authorisation matrix wherever it falls fully within an active rule, so that only exceptions genuinely requiring human judgement reach the MIS team.

## 2. Prerequisites

### a. New Objects to be Created

i. Object: **DER_Unit__c** — child of DER; holds one record per inventory unit on the DER, together with the identity, comment, and discount data captured for that unit.

ii. Object: **DER_Instalment__c** — child of DER_Unit__c; holds the RM's proposed payment-plan instalments for that unit.

iii. Object: **HOD_Discount_Authorisation_Rule__c** — the master configuration table for the HOD Discount Authorisation Matrix.

iv. Object: **HOD_Rule_Property_Code__c** — junction object recording property codes included or excluded by a given rule.

v. Object: **Token_Exception_Rule__c** — configuration table for token-exception authorisation.

vi. Object: **DP_Exception_Rule__c** — configuration table for down-payment exception authorisation.

vii. Object: **DP_Exception_Tier__c** — child of DP_Exception_Rule__c; holds the tiered "X% within Y days" thresholds.

### b. New Custom Metadata Types

i. **DER_Config__mdt** — holds the static separator used when combining the system-generated and free-text portions of a comment, and other tunable values.

ii. **Country_Identity_Document__mdt** — maps each Country to the identity document type required for it (Passport for UAE, National ID for Iraq, extensible to other geographies).

iii. **Agency_Mismatch_Keyword__mdt** — maps keywords/phrases (e.g. "direct deal") to the Agency Type each contradicts, for the comment-consistency check.

### c. Field- and Component-Level Detail

The complete list of new fields required on each of the above objects, together with existing objects being extended, is provided in **Section 5 — Components**.

## 3. Defining the Process

### a. Module A — DER Hygiene & Sanity Checks

#### i. Identity Match Validation

1. Trigger Condition: Whenever an identity document is uploaded to a DER_Unit record and OCR extraction completes.
2. Action: Populate the read-only fields ID_Number_OCR__c, Applicant_Name_OCR__c and Nationality_OCR__c from the OCR service, and compare them against the RM-entered fields ID_Number_RM__c, Applicant_Name__c and Nationality__c.
3. Condition: If the RM-entered values match the OCR-extracted values, set Identity_Match_Status__c = 'Matched'.
4. Else Condition: If the values do not match, set Identity_Match_Status__c = 'Mismatch'. Submission of the DER Unit shall be blocked unless the RM has entered a corrected value into ID_Number_RM__c, so that the discrepancy is attributable to either an OCR misread or a deliberate RM correction.

#### ii. Mandatory Identity Document & Type Verification

1. Trigger Condition: On submission of a DER Unit record.
2. Action: Verify that an identity document is attached (Identity_Document_Attached__c) and that it has been classified as the document type required for the unit's Country__c, per Country_Identity_Document__mdt (Passport for UAE; National ID for Iraq and other applicable geographies).
3. Else Condition: If no document is attached, or the attached document is not verified as the required type, block submission of the DER Unit.

#### iii. Agency Type Derivation & Comment Consistency

1. Trigger Condition: Whenever a DER is saved.
2. Action: Derive Agency_Type__c from Agency__r.Agency_Category__c and present it as a read-only field on the DER.
3. Condition: If the RM comment contains a keyword from Agency_Mismatch_Keyword__mdt that contradicts the derived Agency_Type__c (e.g. "direct deal" recorded while Agency_Type__c is not Direct), set Agency_Comment_Validation_Status__c = 'Inconsistent'.
4. Else Condition: If Agency__c is blank, block submission with the message "Please select an agency before submitting."
5. Else Condition: If the comment is flagged Inconsistent, display a blocking pop-up requiring the RM to correct the comment before the DER can proceed.

#### iv. Structured Selections in Place of Free Text

1. Trigger Condition: Whenever the RM makes a Token Exception, Rebate, DLD Waiver, or Discount selection on a DER Unit.
2. Action: Auto-populate System_Generated_Comment__c from the selected values only (e.g. "DLD waiver = 4%; Discount = 2%"). Concatenate System_Generated_Comment__c with Free_Text_Comment__c using the static separator held in DER_Config__mdt to form Combined_Comment__c, at unit level.
3. Condition: Rebate_Selection__c shall permit only the value 34%; no other rebate percentage may be selected or recorded.

#### v. Instalment Date vs. ACD & Payment-Plan Summation

1. Trigger Condition: On submission of a DER Unit with one or more proposed instalments.
2. Action: Validate that no Instalment_Date__c on the proposed plan exceeds Inventory__r.ACD__c, and that the sum of the proposed Instalment_Percent__c values equals the sum of the actual payment-plan instalments configured on the Inventory record.
3. Else Condition: If either check fails, block submission and display the specific offending instalment(s) against the payment-plan grid.

### b. Module B — HOD Discount Authorisation Matrix

#### i. Configurable Discount Matrix

1. Action: Maintain HOD_Discount_Authorisation_Rule__c records capturing Deal Type, Country, Construction Status, Inventory Type, Bedroom Type (include/exclude), Property Code (include/exclude, via HOD_Rule_Property_Code__c), Price Range, Max Authority %, and the combination of DLD Waiver/Rebate/Discount the rule permits.

#### ii. Date-Bound Versioning

1. Action: Every rule carries a Start_Date__c, an End_Date__c, and a Status__c.
2. Action: To change terms, Sales Ops clones the active rule into a new Draft record, then closes the current rule on activation of the new one (End_Date__c = new rule's Start_Date__c − 1 day; Status__c = 'Closed'; Superseded_By__c populated), so that the change history is preserved in full.

#### iii. Auto-Approval Logic (DERAutoApprovalEngine)

1. Trigger Condition: On submission of a DER.
2. Action: For every DER_Unit on the DER, match it against the active HOD_Discount_Authorisation_Rule__c, Token_Exception_Rule__c, and DP_Exception_Rule__c records applicable on the submission date. Exclusion criteria (bedroom type, property code) are evaluated before inclusion criteria, and the unit's requested discount % must not exceed the matched rule's Max_Authority_Percent__c.
3. Condition: If every unit on the DER matches an active rule within its authorised limits, set Auto_Approval_Status__c = 'Auto-Approved' and Status__c = 'Approved'.
4. Else Condition: If any single unit fails to match an active rule, or exceeds its authorised limit, set Auto_Approval_Status__c = 'Manual Review Required' and route the entire DER to the existing MIS approval process. Partial approval of a DER shall not be permitted under any circumstance.

#### iv. Maker–Checker Control

1. Trigger Condition: On creation or amendment of a rule record (HOD Discount, Token Exception, or DP Exception).
2. Action: Sales Ops, as Maker, submits the Draft rule for approval. Sales Admin HOD, as Checker (Deepesh Moolchandani / Yasir, via the Sales_Admin_HOD_Checkers group), approves or rejects it through a native Salesforce Approval Process.
3. Condition: On approval, Status__c is set to 'Active' (or held as scheduled, and activated automatically on Start_Date__c if that date is in the future).
4. Else Condition: On rejection, Status__c reverts to 'Draft', the record is unlocked, and the rejection comments are made visible to the Maker.

#### v. Token Exception Table

1. Action: Maintain Token_Exception_Rule__c records specifying Min_Token_Percent__c and Balance_Token_Days__c, governed by the same date-bound, maker–checker pattern described above, and driving token-exception auto-approval on the same basis as the Discount Matrix.

#### vi. DP (Down Payment) Exception Table

1. Action: Maintain DP_Exception_Rule__c records with child DP_Exception_Tier__c records, each specifying a Min_DP_Percent__c threshold and the Max_Days__c allowed at that threshold.
2. Action: Sum all DP-related instalments (Instalment_Type__c = 'DP') proposed on the DER Unit, and take the allowed timing as the highest number of days among those instalments; compare this against the Max_Days__c of the tier matching the summed DP percentage.
3. Else Condition: If the actual timing exceeds the allowed Max_Days__c for the applicable tier, the unit does not qualify for auto-approval under this check.

## 4. Conclusion

This implementation ensures that a DER cannot be submitted unless the identity, agency, comment, and payment-plan data recorded against it is valid, and that only DERs falling fully within an active, authorised rule are auto-approved — every unit on a DER must qualify, or the DER as a whole is routed to the existing manual approval process. The maker–checker control on the underlying rule tables, together with full field-history tracking, ensures that the removal of manual review from eligible DERs does not come at the expense of auditability or governance.

## 5. Components

| Component Type | API Name / Identifier | Description |
|---|---|---|
| Object (existing, extended) | DER__c | New fields: Agency_Type__c, Agency_Comment_Validation_Status__c, Free_Text_Comment__c, Auto_Approval_Status__c, Auto_Approval_Reason__c, Auto_Approved_Date__c |
| Object (new) | DER_Unit__c | Child of DER; carries identity, comment, discount-selection, and rule-match fields per inventory unit |
| Object (new) | DER_Instalment__c | Child of DER_Unit__c; carries proposed payment-plan instalments |
| Object (new) | HOD_Discount_Authorisation_Rule__c | Master configuration table for the HOD Discount Authorisation Matrix |
| Object (new) | HOD_Rule_Property_Code__c | Junction object for property-code inclusion/exclusion on a rule |
| Object (new) | Token_Exception_Rule__c | Configuration table for token-exception authorisation |
| Object (new) | DP_Exception_Rule__c | Configuration table for down-payment exception authorisation |
| Object (new) | DP_Exception_Tier__c | Child of DP_Exception_Rule__c; tiered DP%-to-days thresholds |
| Field | DER_Unit__c.Identity_Match_Status__c | Picklist: Matched / Mismatch / Not Verified |
| Field | DER_Unit__c.ID_Number_RM__c / ID_Number_OCR__c | RM-entered vs. OCR-extracted identity number |
| Field | DER_Unit__c.Identity_Document_Attached__c | Checkbox; formula on ContentDocumentLink count |
| Field | DER_Unit__c.Identity_Document_Type_Verified__c | Picklist: Not Verified / Verified / Verification Failed |
| Field | DER__c.Agency_Type__c | Formula (read-only), derived from Agency__r.Agency_Category__c |
| Field | DER_Unit__c.Token_Exception_Selection__c / Rebate_Selection__c / DLD_Waiver_Selection__c / Discount_Selection__c | Structured picklists replacing free text |
| Field | DER_Unit__c.System_Generated_Comment__c / Combined_Comment__c | Auto-built comment fields |
| Field | DER_Unit__c.ACD_Validation_Status__c / Payment_Plan_Match_Status__c | Picklist: Pass / Fail |
| Field | HOD_Discount_Authorisation_Rule__c.Max_Authority_Percent__c, Start_Date__c, End_Date__c, Status__c, Priority__c | Rule configuration and versioning fields |
| Apex Class | DERAutoApprovalEngine | Bulk-safe auto-approval decision engine, invoked on DER submission |
| Apex Class | InstalmentValidationService | ACD and payment-plan summation validation |
| Flow | DER Hygiene Validation (Screen Flow) | Runs Module A checks prior to submission; blocks with inline errors |
| Approval Process | HOD_Discount_Authorisation_Rule__c Approval Process | Maker–checker control (and identical processes on Token_Exception_Rule__c, DP_Exception_Rule__c) |
| Public Group | Sales_Admin_HOD_Checkers | Checker group for all matrix approval processes |
| Permission Set | Sales Ops – Rule Maker | Create/Edit on rule objects while Status__c = 'Draft' |
| Custom Metadata Type | DER_Config__mdt, Country_Identity_Document__mdt, Agency_Mismatch_Keyword__mdt | Configuration values editable without a deployment |

---

## 6. Open Items for Business Confirmation

1. Whether a BR-A1 identity mismatch should hard-block submission or only warn, pending resolution of the OCR accuracy issue.
2. Whether Token Exception rules require the same segmentation (Country/Deal Type/etc.) as the Discount Matrix, or apply globally.
3. Tie-break policy where a unit matches more than one active rule (Priority__c semantics, or a constraint that active rules must not overlap).
4. Rounding tolerance for the payment-plan summation check (BR-A5), to be confirmed with Finance.
5. Treatment of DERs already in progress at go-live (retroactive evaluation vs. forward-only).
6. Current and target membership of the Sales_Admin_HOD_Checkers group.
