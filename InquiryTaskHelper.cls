/*
* @Author      : Venkateswarlu
* @CreatedDate : Feb 2024
* @Name        : InquiryTaskHelper
* @Description : Task Operations
*/
public class InquiryTaskHelper {

    // ── Static state ──────────────────────────────────────────────────────────
    public  static  Map<String, Ameyo_Campaign_Ids__c> mapOfameyoCampaignIds          = Ameyo_Campaign_Ids__c.getAll();
    public  static  Map<Id, Id>                        lanBarMap                      = new Map<Id, Id>();
    public  static  boolean                            isTriggerFired                 = false;
    public  static  Map<String, String>                categoryUpdate                 = new Map<String, String>();
    public  static  Map<String, String>                AmeyoDispistionMapping         = new Map<String, String>();
    public  static  Map<String, String>                AmeyoDispistionMappingRoboDial = new Map<String, String>();
    public  static  List<Telesales_Dialer_Data_PE__e>  teleSalesPEList                = new List<Telesales_Dialer_Data_PE__e>();
    public  static  List<Inquiry__c>                   updateInquiryList              = new List<Inquiry__c>();
    public  final   static Decimal                     roboCallCountLimit             = Integer.valueOf(Label.Robo_Call_Counter_Count);
    public  final   static User                        loggedInUser                   = [SELECT Id, Profile.Name, Name, ProfileId FROM User WHERE Id = :UserInfo.getUserId()];

    private static final String       TASK_TYPE_1                 = 'Call';
    private static final String       HOT_SCORE                   = 'Hot';
    private static final List<String> dispositionActivityOutcomeList = csvLabel(CommonUtility.getAppSetting('DispositionAcitivtyOutcome').Text_Area_Long_Value__c);
    private static final List<String> inquiryRestrictedStatusList    = csvLabel(CommonUtility.getAppSetting('Stop_Calling_Inquiry_Status').Text_Area_Long_Value__c);
    private static final String       dncListId                   = CommonUtility.getAppSetting('DNC_List_Id').Text_Value__c;
    private static final String       expiryDate                  = String.valueOf(System.Date.today().addMonths(1).toStartOfMonth().addDays(-1)).substringBefore(' ') + 'T19:59Z';

    // ── Inner class: carries all maps produced during task-loop iteration ─────
    private class TriggerContext {
        Set<Id>             inquiryIds                                      = new Set<Id>();
        Set<Id>             newTaskInquiryIds                               = new Set<Id>();
        Set<Id>             newTaskIds                                      = new Set<Id>();
        Map<Id, String>     inqRMCommentMap                                 = new Map<Id, String>();
        Map<Id, String>     inqDOSCommentMap                                = new Map<Id, String>();
        Map<Id, String>     inqHOSCommentMap                                = new Map<Id, String>();
        Map<Id, String>     inqHODCommentMap                                = new Map<Id, String>();
        Map<Id, Boolean>    inqRMMeetingDateMap                             = new Map<Id, Boolean>();
        Map<Id, Boolean>    inqDOSMeetingDateMap                            = new Map<Id, Boolean>();
        Map<Id, DateTime>   ameyoCallBacks                                  = new Map<Id, DateTime>();
        Map<Id, String>     inquiryCampaignMap                              = new Map<Id, String>();
        Map<Id, String>     ivrResponses                                    = new Map<Id, String>();
        Map<Id, Inquiry__c> mpInquiries2Update                              = new Map<Id, Inquiry__c>();
        Map<Id, String>     mapOfInqIdTodispostionActivityOutcome           = new Map<Id, String>();
        Map<Id, String>     mapOfInqIdTodispostionActivityOutcomeStopCalling = new Map<Id, String>();
        Map<Id, Id>         mapOfInqInboundIqs                              = new Map<Id, Id>();
        Map<Id, Inquiry__c> mapOfInqInboundIqsToRepush                     = new Map<Id, Inquiry__c>();
        Map<Id, Id>         mapOfInqInboundConnectedIqs                     = new Map<Id, Id>();
        Map<Id, Inquiry__c> mapOfInquiry                                    = new Map<Id, Inquiry__c>();
        Map<Id, String>     mapOfInqIdActivityType                          = new Map<Id, String>();
        Map<Id, String>     mapOfInqIdSubDispType                           = new Map<Id, String>();
        Map<Id, Task>       mapOfSFMCCallBackIds                            = new Map<Id, Task>();
        Map<Id, Id>         mapOfInqWhatsappOptIqs                          = new Map<Id, Id>();
        Map<Id, Task>       mapOfInqOnlineMeet                              = new Map<Id, Task>();
        Map<String, String> mapOfInqTaskId                                  = new Map<String, String>();
        Map<String, Nexmo_Whats_App_Request__c> nexmoRecordUpdate           = new Map<String, Nexmo_Whats_App_Request__c>();
        List<Telesales_Dialer_Data_PE__e> teleSalesDialerPEList             = new List<Telesales_Dialer_Data_PE__e>();
        List<Campaign_Member__c> newCampaignMemberList                      = new List<Campaign_Member__c>();
    }

    // =========================================================================
    // BEFORE TRIGGER
    // =========================================================================
    public static void beforeTriggerHandler(List<Task> lstNew, Map<Id, Task> mpOld,
                                            Boolean isInsert, Boolean isUpdate,
                                            Boolean isDelete, Boolean isUndelete) {
        List<Task>   lbarriertask = new List<Task>();
        List<String> listOfLang   = new List<String>();

        for (Task t : lstNew) {
            if (String.isBlank(t.Activity_Type_3__c) && t.Type != null) {
                t.Activity_Type_3__c = t.Type;
            }

            if (String.isNotBlank(t.Calling_Number__c)
                && (isInsert || (isUpdate && t.Calling_Number__c != mpOld.get(t.Id).Calling_Number__c))) {
                String callingNumber = t.Event_Type__c == 'inbound.call.dial'
                    ? '00' + t.Calling_Number__c : '00' + t.Called_Number__c;
                t.Encrypt_Calling_Number__c = Damac_PhoneEncrypt.encryptPhoneNumber(callingNumber);
            }

            if (t.whatId != null && t.whatId.getSobjectType() == Inquiry__c.sObjectType
                && label.Language_Barrier_Process_Enable == 'true'
                && String.isNotBlank(t.Sub_Disposition_Type__c)
                && t.Activity_Outcome__c == 'Language Barrier') {
                lbarriertask.add(t);
                listOfLang.add(t.Sub_Disposition_Type__c);
                lanBarMap.put(t.whatId, t.whatId);
            }

            if (isUpdate && mpOld.get(t.Id).Status != t.Status && t.Status == 'Completed') {
                t.Completed_DateTime__c = DateTime.now();
            }
        }

        if (lbarriertask.isEmpty()) return;

        List<Id> inquiryTaskOwnerIds = new List<Id>();
        for (String item : System.Label.WA_Inquiry_Task_Users.split(',')) inquiryTaskOwnerIds.add(item);

        Map<Id, Inquiry__c> inqDetails = new Map<Id, Inquiry__c>([
            SELECT Id, OwnerId, Inquiry_Status__c, Inquiry_Source__c,
                   RecordType.Name, Owner.Name, Prypco_Inquiry__c
            FROM   Inquiry__c
            WHERE  Id IN :lanBarMap.keySet()
            AND    Inquiry_Source__c != 'Agent Referral'
        ]);

        String languages = String.join(listOfLang, ',');
        Map<Id, User> mapofUsers = new Map<Id, User>([
            SELECT Id, Name, UserName, Languages_Known__c, Profile.Name, Manager_Role__c
            FROM   User
            WHERE  Languages_Known__c INCLUDES (:languages)
            AND    Profile.Name = 'Telesales Team Lightning'
            AND    (NOT Manager_Role__c LIKE 'Agent%')
            AND    isActive = true
        ]);

        List<Id> ownerIds = new List<Id>();
        for (Task t : [
            SELECT Id, OwnerId FROM Task
            WHERE  OwnerId IN :mapofUsers.keySet()
            AND    WhatId  != null AND What.Type = 'Inquiry__c'
            AND    OwnerId NOT IN :inquiryTaskOwnerIds
            AND    LastModifiedDate = LAST_N_DAYS:5
            ORDER BY LastModifiedDate DESC LIMIT 10
        ]) {
            if (!ownerIds.contains(t.OwnerId)) ownerIds.add(t.OwnerId);
        }

        if (ownerIds.isEmpty()) return;

        for (Task t : lbarriertask) {
            if (!inqDetails.containsKey(t.whatId)) continue;
            Inquiry__c inq = inqDetails.get(t.whatId);
            if (inq.Prypco_Inquiry__c) continue;
            if (!mapofUsers.containsKey(inq.OwnerId)
                || (mapofUsers.get(inq.OwnerId) != null
                    && !mapofUsers.get(inq.OwnerId).Languages_Known__c.containsIgnoreCase(t.Sub_Disposition_Type__c))) {
                t.OwnerId = ownerIds.get(0);
            }
        }
    }

    // =========================================================================
    // AFTER TRIGGER
    // =========================================================================
    public static void afterTriggerHandler(List<Task> lstNew, Map<Id, Task> mpOld,
                                           Boolean isInsert, Boolean isUpdate,
                                           Boolean isDelete, Boolean isUndelete) {
        checkRecursion.firstcallTaskManagerTrigger = true;

        loadCategoryUpdates();
        loadAmeyoMappings();

        // Pre-query inquiry details needed during task-loop evaluation
        Set<Id> taskInquiryIds = new Set<Id>();
        for (Task t : lstNew) {
            if (t.whatId != null && t.whatId.getSobjectType() == Inquiry__c.sObjectType) {
                taskInquiryIds.add(t.whatId);
            }
        }
        Map<Id, Inquiry__c> inqDetails = taskInquiryIds.isEmpty()
            ? new Map<Id, Inquiry__c>()
            : new Map<Id, Inquiry__c>([
                SELECT Id, Inquiry_Status__c, RecordType.Name, Owner.Name, Inquiry_Source__c
                FROM   Inquiry__c WHERE Id IN :taskInquiryIds
              ]);

        Activate_New_Assignment_Process__c process = Activate_New_Assignment_Process__c.getInstance(loggedInUser.Id);

        // Collect all maps from the trigger list
        TriggerContext ctx = collectTaskMaps(lstNew, mpOld, isInsert, isUpdate, inqDetails, process);

        if (ctx.inquiryIds.isEmpty()) return;

        // Nurturing-queue override for high-activity inquiries
        for (Inquiry__c inq : [
            SELECT Id FROM Inquiry__c
            WHERE  Inquiry_Status__c IN ('Not A lead','Budget Constraint','Location Constraint',
                                         'Product Constraint','Postponed Plan to Buy','Potential Agent')
            AND    Ameyo_Campaign_Id__c = '300' AND Id IN :ctx.inquiryIds
            AND    ((Telesales_Activity_Counter__c >= 16 AND Inquiry_Source__c != 'Priority Digital')
                 OR (Telesales_Activity_Counter__c >= 26 AND Inquiry_Source__c  = 'Priority Digital'))
        ]) {
            ctx.mpInquiries2Update.put(inq.Id, new Inquiry__c(Id = inq.Id, OwnerId = System.label.Nurturing_Queue));
        }

        // Resolve campaign virtual numbers
        Map<String, Id> campaignNumberMap = new Map<String, Id>();
        if (!ctx.inquiryCampaignMap.isEmpty()) {
            for (JO_Campaign_Virtual_Number__c cvn : [
                SELECT Id, Related_Campaign__c, Related_Virtual_Number__r.Name, Related_Campaign__r.CreatedDate
                FROM   JO_Campaign_Virtual_Number__c
                WHERE  Related_Virtual_Number__r.Name IN :ctx.inquiryCampaignMap.values()
                AND    Related_Campaign__r.Marketing_Start_Date__c <= TODAY
                AND    Related_Campaign__r.Marketing_End_Date__c   >= TODAY
                ORDER BY Related_Campaign__r.CreatedDate DESC
            ]) {
                campaignNumberMap.put(cvn.Related_Virtual_Number__r.Name, cvn.Related_Campaign__c);
            }
        }

        // Main inquiry processing loop
        Boolean isChanged = processInquiries(ctx, campaignNumberMap, inqDetails, process);

        // DML
        if (!ctx.newCampaignMemberList.isEmpty()) insert ctx.newCampaignMemberList;

        List<Activity_counter__c> counters = buildActivityCounters(ctx.inquiryIds);
        if (!counters.isEmpty()) upsert counters Unique_Key__c;

        if (!ctx.mpInquiries2Update.isEmpty() && !isTriggerFired) {
            isTriggerFired = true;
            DAMAC_Constants.skip_InquiryTrigger = true;
            update ctx.mpInquiries2Update.values();
            if (!ctx.teleSalesDialerPEList.isEmpty()) EventBus.publish(ctx.teleSalesDialerPEList);
            fireUnreachableWhatsapp(ctx.mpInquiries2Update, isChanged);
        }

        if (!ctx.nexmoRecordUpdate.isEmpty()) Database.update(ctx.nexmoRecordUpdate.values(), false);

        if (!ctx.mapOfInqIdTodispostionActivityOutcomeStopCalling.isEmpty()) {
            Map<Inquiry__c, String> stoppingMap = new Map<Inquiry__c, String>();
            for (Id inqId : ctx.mapOfInqIdTodispostionActivityOutcomeStopCalling.keySet()) {
                if (ctx.mapOfInquiry.containsKey(inqId)) stoppingMap.put(ctx.mapOfInquiry.get(inqId), 'No-Input');
            }
            if (!stoppingMap.isEmpty()) createGenesysStopCallingPlatEvent(stoppingMap);
        }

        if (!ctx.mapOfInqInboundIqsToRepush.isEmpty()) {
            genesysUtility.insertPEForInquiryPushAmeyoIDDataload(ctx.mapOfInqInboundIqsToRepush.values());
        }
    }

    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    /** Parse a comma-separated label / custom setting value into a List<String>. */
    private static List<String> csvLabel(String value) {
        return value != null ? value.split(',') : new List<String>();
    }

    private static void loadCategoryUpdates() {
        if (!categoryUpdate.isEmpty()) return;
        for (Inquiry_Country_Code_Categories__c c : [SELECT Name, Category_Update__c FROM Inquiry_Country_Code_Categories__c]) {
            categoryUpdate.put(c.Name, c.Category_Update__c);
        }
    }

    private static void loadAmeyoMappings() {
        if (!AmeyoDispistionMapping.isEmpty()) return;
        for (Ameyo_Dispositions_Inquiry_Status__mdt d : [
            SELECT DeveloperName, Sub_Disposition_Type__c, MasterLabel, Inquiry_Status__c,
                   Activity_outcome__c, Ameyo_Disposition_Name__c, Not_Responded_Activity_Outcomes__c
            FROM   Ameyo_Dispositions_Inquiry_Status__mdt
            WHERE  Genesys_Configurations__c = true
        ]) {
            if (d.Ameyo_Disposition_Name__c != null && d.Inquiry_Status__c != null) {
                AmeyoDispistionMapping.put(d.Ameyo_Disposition_Name__c, d.Inquiry_Status__c);
            }
            if (d.Activity_outcome__c != null && d.Inquiry_Status__c != null) {
                String key = d.Activity_outcome__c.trim()
                    + (d.Sub_Disposition_Type__c != null ? '-' + d.Sub_Disposition_Type__c.trim() : '');
                AmeyoDispistionMapping.put(key.trim(), d.Inquiry_Status__c);
            }
            if (d.Not_Responded_Activity_Outcomes__c) {
                AmeyoDispistionMappingRoboDial.put(d.Ameyo_Disposition_Name__c, d.Inquiry_Status__c);
            }
        }
    }

    /** Build all working maps by iterating the trigger list once. */
    private static TriggerContext collectTaskMaps(
        List<Task> lstNew, Map<Id, Task> mpOld,
        Boolean isInsert, Boolean isUpdate,
        Map<Id, Inquiry__c> inqDetails,
        Activate_New_Assignment_Process__c process
    ) {
        TriggerContext ctx = new TriggerContext();
        List<String> sfmcEventTypes = csvLabel(Label.SFMC_EventType);
        Boolean isAdmin = UserService.isSystemAdminUser();

        for (Task t : lstNew) {
            Task old = isUpdate ? mpOld.get(t.Id) : new Task();

            if (t.whatId == null || t.whatId.getSobjectType() != Inquiry__c.sObjectType) continue;

            // Track newly inserted tasks
            if (isInsert) {
                ctx.newTaskInquiryIds.add(t.whatId);
                ctx.newTaskIds.add(t.Id);
                ctx.inquiryIds.add(t.whatId);
            }

            // Online meeting
            if (isInsert && t.Activity_Type_3__c == 'Online Meeting' && t.Description != '') {
                ctx.mapOfInqOnlineMeet.put(t.WhatId, t);
                ctx.inquiryIds.add(t.whatId);
            }

            // SFMC event types
            if (isInsert && String.isNotBlank(t.Event_Type__c) && sfmcEventTypes.contains(t.Event_Type__c)) {
                ctx.mapOfSFMCCallBackIds.put(t.WhatId, t);
                ctx.inquiryIds.add(t.WhatId);
            }

            // Language barrier
            if (!lanBarMap.isEmpty() && lanBarMap.containsKey(t.whatId)
                && t.Activity_Outcome__c == 'Language Barrier'
                && String.isNotBlank(t.Sub_Disposition_Type__c)
                && !inqDetails.isEmpty() && inqDetails.containsKey(t.whatId)
                && inqDetails.get(t.whatId).Inquiry_Source__c != 'Agent Referral') {
                ctx.inquiryIds.add(t.whatId);
                ctx.mapOfInqTaskId.put(t.WhatId, t.OwnerId);
            }

            // Comment fields
            if (t.RM_Comments__c != null && (isInsert || (isUpdate && t.RM_Comments__c != old.RM_Comments__c))) {
                ctx.inqRMCommentMap.put(t.WhatId, System.now().format() + ' (' + UserInfo.getName() + '): ' + t.RM_Comments__c);
                if (String.isNotBlank(t.Activity_Type_3__c) && t.Activity_Type_3__c.contains('Meeting')) {
                    ctx.inqRMMeetingDateMap.put(t.WhatId, true);
                    ctx.inquiryIds.add(t.whatId);
                }
            }
            if (t.DOS_Comments__c != null && (isInsert || (isUpdate && t.DOS_Comments__c != old.DOS_Comments__c))) {
                ctx.inqDOSCommentMap.put(t.WhatId, System.now().format() + ' (' + UserInfo.getName() + '): ' + t.DOS_Comments__c);
                if (String.isNotBlank(t.Activity_Type_3__c) && t.Activity_Type_3__c.contains('Meeting')) {
                    ctx.inqDOSMeetingDateMap.put(t.WhatId, true);
                    ctx.inquiryIds.add(t.whatId);
                }
            }
            if (t.HOS_Comments__c != null && (isInsert || (isUpdate && t.HOS_Comments__c != old.HOS_Comments__c))) {
                ctx.inqHOSCommentMap.put(t.WhatId, System.now().format() + ' (' + UserInfo.getName() + '): ' + t.HOS_Comments__c);
                ctx.inquiryIds.add(t.whatId);
            }
            if (t.HOD_Comments__c != null && (isInsert || (isUpdate && t.HOD_Comments__c != old.HOD_Comments__c))) {
                ctx.inqHODCommentMap.put(t.WhatId, System.now().format() + ' (' + UserInfo.getName() + '): ' + t.HOD_Comments__c);
                ctx.inquiryIds.add(t.whatId);
            }

            // Disposition / outcome change
            if (t.Dialer_Disposition__c != null || t.Activity_Outcome__c != null) {
                if (isInsert || (isUpdate && (t.Dialer_Disposition__c != old.Dialer_Disposition__c
                                              || t.Activity_Outcome__c  != old.Activity_Outcome__c))) {
                    ctx.inquiryIds.add(t.whatId);
                }
            }

            // Schedule callback
            if ((isInsert && String.isNotBlank(t.Activity_Outcome__c) && t.Activity_Outcome__c.toLowerCase().contains('schedule.callback'))
                || (isUpdate && t.Callback_Datetime__c != old.Callback_Datetime__c)) {
                ctx.ameyoCallBacks.put(t.whatId, t.Callback_Datetime__c);
                ctx.inquiryIds.add(t.whatId);
            }

            // Campaign number
            if ((isInsert && t.Campaign_Number__c != null) || (isUpdate && t.Campaign_Number__c != old.Campaign_Number__c)) {
                ctx.inquiryCampaignMap.put(t.WhatId, t.Campaign_Number__c);
                ctx.inquiryIds.add(t.whatId);
            }

            // Dialer disposition + activity outcome
            if (t.Dialer_Disposition__c != null && t.Activity_Outcome__c != null) {
                String dispo = t.Dialer_Disposition__c + ' ' + t.Activity_Outcome__c;
                if (isInsert && t.Event_Type__c == 'inbound.robo.dial') {
                    ctx.ivrResponses.put(t.WhatId, t.Activity_Outcome__c);
                    ctx.inquiryIds.add(t.whatId);
                    if (dispositionActivityOutcomeList.contains(dispo)) {
                        ctx.mapOfInqIdTodispostionActivityOutcomeStopCalling.put(t.WhatId, dispo);
                    }
                }
                if (isInsert && t.Event_Type__c == 'inbound.call.dial') {
                    if (t.Dialer_Disposition__c == 'CALL_HANGUP') ctx.mapOfInqInboundIqs.put(t.WhatId, t.WhatId);
                    if (t.Dialer_Disposition__c == 'CONNECTED')   ctx.mapOfInqInboundConnectedIqs.put(t.WhatId, t.WhatId);
                }
                if (isInsert && t.Event_Type__c == 'Whatsapp/Unsubscribe') {
                    ctx.mapOfInqWhatsappOptIqs.put(t.WhatId, t.WhatId);
                }
                ctx.mapOfInqIdTodispostionActivityOutcome.put(t.WhatId, dispo);
                ctx.mapOfInqIdActivityType.put(t.WhatId, t.Activity_Outcome__c);
                ctx.inquiryIds.add(t.whatId);
                if (String.isNotBlank(t.Sub_Disposition_Type__c)) ctx.mapOfInqIdSubDispType.put(t.WhatId, t.Sub_Disposition_Type__c);
            }

            // Ameyo status update
            if (process.Activate_Inq_Status_Update_from_Task_Trg__c) {
                applyAmeyoStatusUpdate(t, inqDetails, ctx, isAdmin);
            }
        }
        return ctx;
    }

    /** Determine and store Ameyo-driven inquiry status for a single task. */
    private static void applyAmeyoStatusUpdate(
        Task t, Map<Id, Inquiry__c> inqDetails, TriggerContext ctx, Boolean isAdmin
    ) {
        String profile = loggedInUser.Profile.Name;
        if (profile != 'Telesales Team Lightning' && !isAdmin
            && profile != 'Ameyo CTI' && profile != 'SystemAdminAPIUSerOnly') return;

        if (t.Event_Type__c != null && t.Event_Type__c.contains('Ziwo')) return;
        if (t.Event_Type__c == 'inbound.robo.dial' && t.Dialer_Disposition__c == 'NOT-CONNECTED') return;
        if (inqDetails.containsKey(t.whatId)
            && inqDetails.get(t.whatId).RecordType.Name == 'Pre Inquiry'
            && inqDetails.get(t.whatId).Inquiry_Status__c == 'Meeting Scheduled') return;

        String ameyoStatus = resolveAmeyoStatus(t);
        if (String.isBlank(ameyoStatus)) return;

        List<String> nurturingStatuses = csvLabel(Label.Robo_call_Nurturing_queue_statuses);
        if (nurturingStatuses.contains(ameyoStatus)) {
            ctx.mpInquiries2Update.put(t.WhatId,
                new Inquiry__c(Id = t.WhatId, Inquiry_Status__c = ameyoStatus, OwnerId = System.label.Nurturing_Queue));
        } else {
            ctx.mpInquiries2Update.put(t.WhatId, new Inquiry__c(Id = t.WhatId, Inquiry_Status__c = ameyoStatus));
        }
        ctx.inquiryIds.add(t.whatId);

        if (inquiryRestrictedStatusList.contains(ameyoStatus)) {
            ctx.teleSalesDialerPEList.add(
                genesysUtility.returnPlatformEventRecord('Add Inquiry to DNC', '', t.WhatId, '', dncListId, '', expiryDate, ''));
        }
    }

    /** Resolve which Ameyo inquiry status applies to a task. */
    private static String resolveAmeyoStatus(Task t) {
        String status = '';
        if (t.Dialer_Disposition__c != null && AmeyoDispistionMapping.containsKey(t.Dialer_Disposition__c)) {
            status = AmeyoDispistionMapping.get(t.Dialer_Disposition__c);
        }
        if (t.Activity_Outcome__c != null && t.Sub_Disposition_Type__c != null) {
            String key = t.Activity_Outcome__c + '-' + t.Sub_Disposition_Type__c;
            status = AmeyoDispistionMapping.containsKey(key)
                ? AmeyoDispistionMapping.get(key)
                : (AmeyoDispistionMapping.containsKey(t.Activity_Outcome__c) ? AmeyoDispistionMapping.get(t.Activity_Outcome__c) : status);
        }
        if (t.Activity_Outcome__c != null && t.Sub_Disposition_Type__c == null
            && AmeyoDispistionMapping.containsKey(t.Activity_Outcome__c)) {
            status = AmeyoDispistionMapping.get(t.Activity_Outcome__c);
        }
        return status;
    }

    /** Build activity-counter upsert list. */
    private static List<Activity_counter__c> buildActivityCounters(Set<Id> inquiryIds) {
        List<Activity_counter__c> result = new List<Activity_counter__c>();
        for (AggregateResult a : [
            SELECT COUNT(Id) countval, WhatId inq, OwnerId own
            FROM   Task WHERE WhatId IN :inquiryIds GROUP BY WhatId, OwnerId
        ]) {
            Activity_counter__c ac = new Activity_counter__c();
            ac.Count__c            = Integer.valueOf(a.get('countval'));
            ac.Inquiry__c          = String.valueOf(a.get('inq'));
            ac.Inquiry_Owner__c    = String.valueOf(a.get('own'));
            ac.Unique_Key__c       = String.valueOf(ac.Inquiry__c) + String.valueOf(ac.Inquiry_Owner__c) + 'By Owner';
            ac.type_of_counter__c  = 'By Owner';
            result.add(ac);
        }
        return result;
    }

    /** Fire WA not-reachable messages for qualifying inquiries — once per day only. */
    private static void fireUnreachableWhatsapp(Map<Id, Inquiry__c> mpInquiries2Update, Boolean isChanged) {
        if (!isChanged) return;
        List<String> whatsAppTriggerCounter = csvLabel(Label.Inquiry_UnReachable_Whatsapp_Counter);
        ID ameyoDialerQueueId = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Ameyo_Dialer_Queue'].Id;
        Set<Id> unReachableInquiryIds = new Set<Id>();
        for (Inquiry__c inq : [
            SELECT Id, Telesales_Activity_Counter__c, OwnerId, Call_Status__c, WhatsappConsent__c,
                   (SELECT Id FROM Tasks WHERE CreatedDate = TODAY ORDER BY CreatedDate ASC LIMIT 2)
            FROM   Inquiry__c
            WHERE  Id IN :mpInquiries2Update.values() AND Inquiry_Source__c != 'Agent Referral'
        ]) {
            Decimal cnt = inq.Telesales_Activity_Counter__c;
            // Tasks.size() == 1 → first call of the day → send WA
            // Tasks.size() > 1 → already called today → skip to avoid duplicate WA
            if (cnt >= 1 && whatsAppTriggerCounter.contains(String.valueOf(cnt))
                && inq.OwnerId == ameyoDialerQueueId
                && inq.Call_Status__c == 'Attempted'
                && inq.WhatsappConsent__c != 'Whatsapp/Unsubscribe'
                && inq.Tasks.size() == 1) {
                unReachableInquiryIds.add(inq.Id);
            }
        }
        if (!unReachableInquiryIds.isEmpty() && Label.RR_LoggedIn_User_Name == 'true') {
            Genesys_UnReachableWhatsappController.initiateNotReachableWAMessages(unReachableInquiryIds);
        }
    }

    /** Main inquiry processing loop — iterates queried inquiries and applies all business rules. */
    private static Boolean processInquiries(
        TriggerContext ctx,
        Map<String, Id> campaignNumberMap,
        Map<Id, Inquiry__c> inqDetails,
        Activate_New_Assignment_Process__c process
    ) {
        Boolean isChanged = false;

        String query = Genesys_InquiryHelper.inquiryQuery();
        query += ' , (SELECT Id, Status__c FROM Events ORDER BY Status__c ASC),';
        query += ' (SELECT Id, Activity_Outcome__c, Subject, Dialer_Disposition__c, Type, CallType,';
        query += '  Event_type__c, whatId, CreatedDate, Status, OwnerId, Owner.Profile.Name, Sub_Disposition_type__c, Callback_Datetime__c';
        query += '  FROM Tasks ORDER BY CreatedDate DESC),';
        query += ' (SELECT Id, OwnerId, Inquiry__c FROM Nexmo_Whats_App_Requests__r),';
        query += ' (SELECT Campaign__c, Inquiry__c FROM Associated_Campaigns__r)';
        query += '  FROM Inquiry__c WHERE Id IN :inquiryIds';

        Set<Id> inquiryIds = ctx.inquiryIds;

        List<String> roboConvertStatuses = csvLabel(Label.Robo_Call_Inquiry_Status);
        List<String> nurturingStatuses   = csvLabel(Label.Robo_call_Nurturing_queue_statuses);
        List<String> notALeadOutcomes    = csvLabel(Label.Robo_Call_Not_a_Lead_Activity_Outcome_List);
        List<String> damacQueueStatuses  = csvLabel(Label.Inquiry_Damac_Queue_IQ_Status);
        List<String> unreachableSubTypes = csvLabel(Label.Inquiry_Unreachable_Sub_Disposition_Type);

        for (Inquiry__c inq : Database.query(query)) {
            ctx.mapOfInquiry.put(inq.Id, inq);

            Integer completedEvents = 0, completedTasks = 0, activeEvents = 0,
                    activeTasks = 0, telesalesTasks = 0, roboCallCount = 0;

            Inquiry__c upd = ctx.mpInquiries2Update.containsKey(inq.Id)
                ? ctx.mpInquiries2Update.get(inq.Id) : new Inquiry__c(Id = inq.Id);

            if (upd.Inquiry_Status__c == null) {
                upd.Inquiry_Status__c     = inq.Inquiry_Status__c;
                upd.Mobile_CountryCode__c = inq.Mobile_CountryCode__c;
            }

            // Activate new inquiry on first task
            if (upd.Inquiry_Status__c.equalsIgnoreCase(DAMAC_Constants.INQUIRY_NEW_STATUS)
                && process.Activate_Inq_Status_Update_from_Task_Trg__c
                && String.isNotBlank(inq.Inquiry_Status__c)
                && inq.Inquiry_Status__c.equalsIgnoreCase(DAMAC_Constants.INQUIRY_NEW_STATUS)) {
                upd.By_Pass_Validation__c = true;
                upd.Inquiry_Status__c     = DAMAC_Constants.INQUIRY_ACTIVE_STATUS;
                upd.Inquiry_Sub_Status__c = 'Call Attempted';
                upd.Disposition__c        = 'Call Attempted';
            }

            // Event counters
            for (Event ev : inq.Events) {
                if (String.isNotBlank(ev.Status__c)) {
                    if (ev.Status__c.containsIgnoreCase(DAMAC_Constants.EVENT_COMPLETED_STATUS)) completedEvents++;
                    if (ev.Status__c.containsIgnoreCase(DAMAC_Constants.EVENT_PLANNED_STATUS))   activeEvents++;
                }
            }

            // Task counters + call status + score
            String callStatus = 'Attempted';
            for (Task t : inq.Tasks) {
                if (t.Event_Type__c == 'inbound.robo.dial' && t.Status == 'Completed') roboCallCount++;

                String profile = t.Owner.Profile.Name;
                if (t.Event_Type__c != 'Whatsapp/Inbound' && t.Event_Type__c != 'Whatsapp/Unsubscribe'
                    && ((profile != null && profile.startsWith('Telesales'))
                        || label.Telesales_Activity_Counter_OwnerIds.contains(t.OwnerId)
                        || label.Telesales_Activity_Counter_OwnerIds_Ameyo.contains(t.OwnerId))
                    && (String.isBlank(t.Event_Type__c) || !t.Event_Type__c.startsWith('SFMC'))) {
                    telesalesTasks++;
                }

                if (String.isNotBlank(t.Status)) {
                    if (t.Status.containsIgnoreCase(DAMAC_Constants.EVENT_COMPLETED_STATUS)) completedTasks++;
                    if (DAMAC_Constants.ACTIVE_TASK_STATUS.containsIgnoreCase(t.Status))     activeTasks++;
                }
                if (t.Dialer_Disposition__c == 'CONNECTED' && callStatus != 'Connected'
                    && t.Sub_Disposition_Type__c != 'Redirected_to_voicemail') {
                    callStatus = 'Connected';
                }
                if (process.Activate_Inq_Status_Update_from_Task_Trg__c
                    && String.isNotBlank(t.Subject) && t.Subject.containsIgnoreCase(TASK_TYPE_1)) {
                    upd.Inquiry_Score__c             = HOT_SCORE;
                    upd.Inquiry_Score_Last_Update__c = System.today();
                }
            }

            // New task inserted → check if any existing task has a future schedule.callback
            if (ctx.newTaskInquiryIds.contains(inq.Id)) {
                for (Task t : inq.Tasks) {
                    if (ctx.newTaskIds.contains(t.Id)) continue;
                    if (t.Activity_Outcome__c != null
                        && t.Activity_Outcome__c.equalsIgnoreCase('schedule.callback')
                        && t.Callback_Datetime__c != null
                        && t.Callback_Datetime__c > DateTime.now()) {
                        createGenesysStopCallingPlatEvent(new Map<Inquiry__c, String>{ inq => 'schedule.callback' });
                        break;
                    }
                }
            }

            // Counters
            if (upd.Telesales_Activity_Counter__c != telesalesTasks) {
                upd.Telesales_Activity_Counter__c = telesalesTasks;
                isChanged = true;
            }
            if (upd.Robo_Call_Counter__c != roboCallCount) upd.Robo_Call_Counter__c = roboCallCount;

            // Connected → stop calling
            if (!ctx.mapOfInqInboundConnectedIqs.isEmpty()
                && ctx.mapOfInqInboundConnectedIqs.containsKey(inq.Id)
                && inq.OwnerId != label.Ameyo_Dialer_Queue_Id) {
                createGenesysStopCallingPlatEvent(new Map<Inquiry__c, String>{ inq => 'CONNECTED' });
            }

            // WhatsApp unsubscribe
            if (!ctx.mapOfInqWhatsappOptIqs.isEmpty() && ctx.mapOfInqWhatsappOptIqs.containsKey(inq.Id)) {
                createGenesysStopCallingPlatEvent(new Map<Inquiry__c, String>{ inq => 'WhatsApp' });
                upd.WhatsappConsent__c = 'Whatsapp/Unsubscribe';
            }

            // Inbound hangup → repush to campaign
            if (!ctx.mapOfInqInboundIqs.isEmpty() && ctx.mapOfInqInboundIqs.containsKey(inq.Id)
                && inq.OwnerId == label.Ameyo_Dialer_Queue_Id) {
                createGenesysStopCallingPlatEvent(new Map<Inquiry__c, String>{ inq => 'CALL_HANGUP' });
                String campaign = upd.Mobile_CountryCode__c == 'United Arab Emirates: 00971'
                    ? Label.Inquiry_UAE_Fresh_Leads_Salesforce_Campaign_Number : '119';
                upd.Ameyo_ID_Dataload__c = campaign;
                upd.Inquiry_Status__c    = 'New';
                inq.Inquiry_Status__c    = 'New';
                inq.Ameyo_customer_id__c = null;
                inq.Ameyo_ID_Dataload__c = campaign;
                inq.Meeting_type__c      = null;
                if (inq.Prypco_Inquiry__c) { upd.Ameyo_ID_Dataload__c = '6999'; inq.Ameyo_ID_Dataload__c = '6999'; }
                ctx.mapOfInqInboundIqsToRepush.put(inq.Id, inq);
                if (inq.Inquiry_Status__c == 'Do Not Disturb') genesysUtility.clearInquiryFromDNCInGenesys(inq.Id);
            }

            // Online meeting link
            if (!ctx.mapOfInqOnlineMeet.isEmpty() && ctx.mapOfInqOnlineMeet.containsKey(inq.Id)) {
                upd.Online_Meeting_Link__c = ctx.mapOfInqOnlineMeet.get(upd.Id).Description;
            }

            // SFMC re-engagement
            if (!ctx.mapOfSFMCCallBackIds.isEmpty() && ctx.mapOfSFMCCallBackIds.containsKey(inq.Id)) {
                if (inq.OwnerId == label.Ameyo_Dialer_Queue_Id
                    || inq.OwnerId == label.DAMAC_Queue || inq.OwnerId == label.Nurturing_Queue) {
                    String campaign = upd.Mobile_CountryCode__c == 'United Arab Emirates: 00971'
                        ? Label.Inquiry_UAE_Fresh_Leads_Salesforce_Campaign_Number : '119';
                    upd.Ameyo_ID_Dataload__c  = campaign;
                    upd.Inquiry_Status__c      = 'New';
                    upd.Call_back_Date_time__c = ctx.mapOfSFMCCallBackIds.get(upd.Id).Callback_Datetime__c;
                    inq.Inquiry_Status__c      = 'New';
                    inq.Ameyo_customer_id__c   = null;
                    inq.Ameyo_ID_Dataload__c   = campaign;
                    inq.Meeting_type__c        = null;
                    inq.Call_back_Date_time__c = ctx.mapOfSFMCCallBackIds.get(upd.Id).Callback_Datetime__c;
                    ctx.mapOfInqInboundIqsToRepush.put(inq.Id, inq);
                }
            }

            // IVR / Robo-dial response
            if (ctx.ivrResponses.containsKey(inq.Id)) {
                String ivrResponse = ctx.ivrResponses.get(inq.Id);
                if (notALeadOutcomes.contains(ivrResponse)) {
                    if (inq.Robo_Call_Inquiry_Status__c == null) {
                        inq.Robo_Call_Inquiry_Status__c = inq.Inquiry_Status__c;
                        upd.Robo_Call_Inquiry_Status__c = inq.Inquiry_Status__c;
                    }
                    if (roboConvertStatuses.contains(inq.Robo_Call_Inquiry_Status__c)) {
                        upd.Inquiry_Status__c = 'Not a lead';
                        upd.OwnerId           = System.label.DAMAC_Queue;
                    }
                    if (nurturingStatuses.contains(inq.Robo_Call_Inquiry_Status__c)) {
                        upd.OwnerId           = System.label.Nurturing_Queue;
                        upd.Inquiry_Status__c = inq.Robo_Call_Inquiry_Status__c;
                    }
                } else {
                    if (upd.Robo_Call_Counter__c >= roboCallCountLimit
                        && inqDetails.containsKey(upd.Id) && inqDetails.get(upd.Id).Owner.Name == 'Ameyo Dialer Queue') {
                        if (roboConvertStatuses.contains(inq.Robo_Call_Inquiry_Status__c)) {
                            upd.Inquiry_Status__c = 'Unreachable - Not responding';
                            upd.OwnerId           = System.label.Nurturing_Queue;
                        }
                        if (inq.Robo_Call_Inquiry_Status__c == 'Not a lead'
                            || inq.Robo_Call_Inquiry_Status__c == 'Not a Lead') {
                            upd.Inquiry_Status__c = 'Not a lead';
                            upd.OwnerId           = System.label.DAMAC_Queue;
                        }
                        if (nurturingStatuses.contains(inq.Robo_Call_Inquiry_Status__c)) {
                            upd.OwnerId           = System.label.Nurturing_Queue;
                            upd.Inquiry_Status__c = inq.Robo_Call_Inquiry_Status__c;
                        }
                    }
                }
            }

            // First activity date
            if (inq.Inquiry_Status__c != 'Closed Won' && inq.Inquiry_Status__c != 'Closed Lost'
                && inq.First_Activity_Date__c == null && !inq.Tasks.isEmpty()) {
                upd.First_Activity_Date__c = inq.Tasks[0].CreatedDate;
            }

            // Activity counters on inquiry
            if (inq.Activity_Counter__c               != (activeEvents + activeTasks + completedEvents + completedTasks)
                || inq.Completed_Activities_Counter__c != (completedEvents + completedTasks)
                || inq.All_Activities_Counter__c       != (inq.Events.size() + inq.Tasks.size())) {
                upd.Completed_Activities_Counter__c = completedEvents + completedTasks;
                upd.All_Activities_Counter__c       = inq.Events.size() + inq.Tasks.size();
                upd.By_Pass_Validation__c           = true;
                upd.Last_Activity_Date__c           = System.now();
            }

            // Comments
            if (ctx.inqRMCommentMap.containsKey(inq.Id)) {
                upd.Comments__c = ctx.inqRMCommentMap.get(inq.Id) + '\n\n' + inq.Comments__c;
                if (ctx.inqRMMeetingDateMap.containsKey(upd.Id) && ctx.inqRMMeetingDateMap.get(upd.Id)) {
                    upd.RM_Last_Meeting_Comment_Date__c = System.now();
                    upd.Trigger_DOS_Notification__c     = true;
                }
            }
            if (ctx.inqDOSCommentMap.containsKey(inq.Id)) {
                upd.DOS_Comments__c = ctx.inqDOSCommentMap.get(inq.Id) + '\n\n' + inq.DOS_Comments__c;
                if (ctx.inqDOSMeetingDateMap.containsKey(upd.Id) && ctx.inqDOSMeetingDateMap.get(upd.Id)) {
                    upd.DOS_Last_Meeting_Comment_Date__c = System.now();
                }
            }
            if (ctx.inqHOSCommentMap.containsKey(inq.Id)) {
                upd.HOS_Comments__c = ctx.inqHOSCommentMap.get(inq.Id) + '\n\n' + inq.HOS_Comments__c;
            }
            if (ctx.inqHODCommentMap.containsKey(inq.Id)) {
                upd.HOD_Comments__c = ctx.inqHODCommentMap.get(inq.Id) + '\n\n' + inq.HOD_Comments__c;
            }

            if (ctx.mapOfInqIdTodispostionActivityOutcome.containsKey(inq.Id)) {
                upd.Dialer_Disposition_Activity_Outcome__c = ctx.mapOfInqIdTodispostionActivityOutcome.get(inq.Id);
            }

            if (!inq.Tasks.isEmpty() && inq.Call_Status__c != callStatus) upd.Call_Status__c = callStatus;

            if (ctx.ameyoCallBacks.containsKey(upd.Id)) upd.Ameyo_Callback_Datetime__c = ctx.ameyoCallBacks.get(upd.Id);

            // Campaign member
            if (!ctx.inquiryCampaignMap.isEmpty() && !campaignNumberMap.isEmpty()
                && inq.Campaign__c != campaignNumberMap.get(ctx.inquiryCampaignMap.get(inq.Id))) {
                Set<Id> assoCampIds = new Set<Id>();
                for (Campaign_Member__c cm : inq.Associated_Campaigns__r) assoCampIds.add(cm.Campaign__c);
                Id targetCamp = campaignNumberMap.get(ctx.inquiryCampaignMap.get(inq.Id));
                if (!assoCampIds.contains(targetCamp)) {
                    ctx.newCampaignMemberList.add(new Campaign_Member__c(Campaign__c = targetCamp, Inquiry__c = inq.Id));
                }
            }

            // Country-code HOD rule
            if (inq.Mobile_CountryCode__c != null && categoryUpdate.containsKey(inq.Mobile_CountryCode__c)) {
                upd.Rule_For_HOD__c = categoryUpdate.get(inq.Mobile_CountryCode__c);
            }

            // IVR response label
            upd.Latest_IVR_Response__c = ctx.ivrResponses.containsKey(inq.Id)
                ? ctx.ivrResponses.get(upd.Id) : '';
            if (String.isNotEmpty(upd.Latest_IVR_Response__c)
                && (upd.Latest_IVR_Response__c == 'No-Input'
                    || (!AmeyoDispistionMappingRoboDial.isEmpty()
                        && AmeyoDispistionMappingRoboDial.containsKey(upd.Latest_IVR_Response__c)))) {
                upd.Latest_IVR_Response__c = 'No-Input';
                if (upd.Robo_Call_Counter__c < roboCallCountLimit
                    && inqDetails.containsKey(upd.Id) && inqDetails.get(upd.Id).Owner.Name == 'Ameyo Dialer Queue') {
                    upd.Inquiry_Status__c = 'Unreachable - Not responding';
                }
            } else if (upd.Latest_IVR_Response__c == 'Not-Interested') {
                upd.Latest_IVR_Response__c = '2';
            } else if (String.isNotBlank(upd.Latest_IVR_Response__c)) {
                upd.Latest_IVR_Response__c = '1';
            } else {
                upd.Latest_IVR_Response__c = '';
            }

            if (upd.Latest_IVR_Response__c == 'No-Input') upd.Ameyo_Customer_Id__c = null;

            // DAMAC-queue owner override
            if (ctx.mapOfInqIdActivityType.containsKey(inq.Id) && !damacQueueStatuses.isEmpty()
                && damacQueueStatuses.contains(ctx.mapOfInqIdActivityType.get(inq.Id))) {
                String outcome = ctx.mapOfInqIdActivityType.get(inq.Id);
                if (outcome == 'Unreachable') {
                    if (!ctx.mapOfInqIdSubDispType.isEmpty()
                        && unreachableSubTypes.contains(ctx.mapOfInqIdSubDispType.get(inq.Id))) {
                        upd.OwnerId = System.label.DAMAC_Queue;
                    }
                } else {
                    upd.OwnerId = System.label.DAMAC_Queue;
                }
            }

            // Language barrier owner reassignment
            if (!ctx.mapOfInqTaskId.isEmpty() && ctx.mapOfInqTaskId.containsKey(inq.Id)) {
                upd.OwnerId = ctx.mapOfInqTaskId.get(inq.Id);
                for (Nexmo_Whats_App_Request__c nr : inq.Nexmo_Whats_App_Requests__r) {
                    ctx.nexmoRecordUpdate.put(nr.Id, new Nexmo_Whats_App_Request__c(Id = nr.Id, OwnerId = upd.OwnerId));
                }
            }

            ctx.mpInquiries2Update.put(upd.Id, upd);
        }
        return isChanged;
    }

    // =========================================================================
    // PUBLIC METHODS (unchanged signatures)
    // =========================================================================

    public static void createGenesysStopCallingPlatEvent(Map<Inquiry__c, String> mapOfInqIdTodispostionActivityOutcomeStopCalling) {
        List<Telesales_Dialer_Push__c>    dialerDataList    = new List<Telesales_Dialer_Push__c>();
        List<Telesales_Dialer_Data_PE__e> stopCallingPEList = new List<Telesales_Dialer_Data_PE__e>();
        String ameyoDialerQueueEmail = CommonUtility.getAppSetting('Ameyo_Dialer_Queue_Email').Text_Value__c;

        for (Inquiry__c inq : mapOfInqIdTodispostionActivityOutcomeStopCalling.keySet()) {
            String disposition  = mapOfInqIdTodispostionActivityOutcomeStopCalling.get(inq);
            String dataloadIden = (disposition != null && disposition.equalsIgnoreCase('schedule.callback'))
                                  ? 'schedule.callback' : 'Stop Calling Inquiry';
            String batchName    = inq.Ameyo_Campaign_Id__c + ' ' + String.valueOf(System.now());
            dialerDataList.add(Genesys_ParseCSVToDeleteInquiry.returnTeleSalesDialerRecord(inq, batchName, ameyoDialerQueueEmail, mapOfameyoCampaignIds, dataloadIden));
            Telesales_Dialer_Data_PE__e pe = new Telesales_Dialer_Data_PE__e();
            pe.Batch_Name__c          = batchName;
            pe.Total_No_Of_Records__c = '1';
            pe.Dataload_Idetifier__c  = dataloadIden;
            stopCallingPEList.add(pe);
        }
        if (!dialerDataList.isEmpty())    insert dialerDataList;
        if (!stopCallingPEList.isEmpty()) EventBus.publish(stopCallingPEList);
    }

    public static void createGenesysStopCallingPE(Map<Id, String> mapOfInqIdTodispostionActivityOutcomeStopCalling) {
        Map<Id, Inquiry__c> mapOfInquiries = new Map<Id, Inquiry__c>([
            SELECT Id, Ameyo_Campaign_Id__c FROM Inquiry__c
            WHERE  Id IN :mapOfInqIdTodispostionActivityOutcomeStopCalling.keySet()
            AND    Ameyo_Campaign_Id__c != ''
        ]);
        for (Id inqId : mapOfInqIdTodispostionActivityOutcomeStopCalling.keySet()) {
            if (!mapOfInquiries.containsKey(inqId)) continue;
            if (mapOfInqIdTodispostionActivityOutcomeStopCalling.get(inqId) == null) continue;
            String campId = mapOfInquiries.get(inqId).Ameyo_Campaign_Id__c;
            if (mapOfameyoCampaignIds == null || !mapOfameyoCampaignIds.containsKey(campId)
                || mapOfameyoCampaignIds.get(campId) == null) continue;
            teleSalesPEList.add(genesysUtility.returnPlatformEventRecord(
                'Stop Calling Inquiry',
                mapOfameyoCampaignIds.get(campId).Genesys_Campaign_Id__c,
                inqId,
                mapOfameyoCampaignIds.get(campId).Genesys_Calling_List_Id__c,
                '', '', '', ''
            ));
        }
        if (!teleSalesPEList.isEmpty()) EventBus.publish(teleSalesPEList);
    }
}
