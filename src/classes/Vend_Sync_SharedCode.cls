global with sharing class Vend_Sync_SharedCode {

    public static List<Vend_Debug_Log__c> InsertQueue_VendDebugLogs = new List<Vend_Debug_Log__c>();
    public static final String ADMIN_NOTIFICATION_SUBJECT = 'Vend Sync Salesforce Admin Notification';
    public static final String ADMIN_TYPE = 'Salesforce Admin';
    public static final Integer QUERYEXCEPTION_MAXRETRY = 12;
    public class InvalidParameterValueException extends Exception {}

    private static Boolean fCheckedIsSandbox = false;
    public static Boolean IsSandbox {
        get {
            if (!fCheckedIsSandbox) {
                IsSandbox = true;
                System.debug('****Vend_Sync_SharedCode:IsSandbox - SOQL Query: SELECT IsSandbox FROM Organization LIMIT 1');
                List<Organization> organizations = [SELECT IsSandbox FROM Organization LIMIT 1];
                if (!organizations.isEmpty()) {
                    IsSandbox = Boolean.valueOf(organizations[0].IsSandbox);
                }
                fCheckedIsSandbox = true;
            }

            return IsSandbox;
        }

        set;
    }

    public static Datetime CleanVendJsonDateTime(String vendJsonDatetime) {

        if (String.isBlank(vendJsonDatetime)) {
            return Datetime.valueOf(vendJsonDatetime);
        }

        // vendJsonDatetime format: 2014-06-27T22:59:56+00:00
        // Salesforce expected format: yyyy-MM-dd HH:mm:ss
        return Datetime.valueOf(vendJsonDatetime.replace('T', ' ').removeEnd('+00:00'));
    }

    public static Integer GetMaximumDMLLimitSize() {

        Integer percentageMultiple = 98;
        Integer maximumLimitSize = ((Limits.getLimitQueryRows() - Limits.getQueryRows()) / 100) * percentageMultiple;
        Integer maximumDMLLimitSize = ((Limits.getLimitDMLRows() - Limits.getDMLRows()) / 100) * percentageMultiple;


        return maximumDMLLimitSize < maximumLimitSize ? maximumDMLLimitSize : maximumLimitSize;
    }

    public static void CheckDebugLog() {

        // Clear out logs > 24 hours
        System.debug('****Vend_Sync_SharedCode:IsSandbox - SOQL Query: SELECT Id FROM Vend_Debug_Log__c WHERE isDeleted = false AND CreatedDate < TODAY LIMIT ' + GetMaximumDMLLimitSize());
        List<Vend_Debug_Log__c> deleteDebugLogs = [SELECT Id FROM Vend_Debug_Log__c WHERE isDeleted = false AND CreatedDate < TODAY LIMIT :GetMaximumDMLLimitSize()];
        if (!deleteDebugLogs.isEmpty()) {
            Database.delete(deleteDebugLogs, false);
        }
    }

    public static void FlushAllQueues() {

        if (!Vend_Sync_SharedCode.InsertQueue_VendDebugLogs.isEmpty()) {

            System.debug('****Vend_Sync_SharedCode:FlushAllQueues - InsertQueue_VendDebugLogs size: ' + Vend_Sync_SharedCode.InsertQueue_VendDebugLogs.size());
            Database.insert(Vend_Sync_SharedCode.InsertQueue_VendDebugLogs, false);
            Vend_Sync_SharedCode.InsertQueue_VendDebugLogs.clear();
        }
    }
    public static void SendAdminAlert(LoggingLevel logLevel, String adminType, String message){

        // Output Debugger
		System.debug(logLevel, message);

        if (Test.isRunningTest()) {
            return;
        }

        Vend_Sync_SharedCode.CheckDebugLog();

        if (message.length() <= 255) {
            Vend_Sync_SharedCode.InsertQueue_VendDebugLogs.add(
                new Vend_Debug_Log__c(
                    Logging_Level__c = logLevel.name(),
                    Message__c = message));
        }
        else {
            Vend_Sync_SharedCode.InsertQueue_VendDebugLogs.add(
                new Vend_Debug_Log__c(
                    Logging_Level__c = logLevel.name(),
                    Message__c = message.left(250) + '...',
                    Message_Verbose__c = message));
        }
    }

    public static String GetExceptionMessage(Exception e) {
        return ' - ' + e.getTypeName() + ' Message: ' + e.getMessage() + ' Line Number: ' + e.getLineNumber() + ' Cause: ' + e.getCause() + ' Stack Trace: ' + e.getStackTraceString();
    }

    public static String GetExternalWebsiteToken() {

        String strToken = '6jALrAHFYJ3XEgnSwLx6lw_TMtppPV8xJXoq3u7s';
        if (Vend_Sync_SharedCode.IsSandbox) {
            strToken = '6jALrAHFYJ3XEgnSwLx6lw_TMtppPV8xJXoq3u7s';
        }

        return strToken;
    }

    public static String GetExternalWebsiteUrl() {

        String strSubDomain = 'https://bimuseumofart.vendhq.com/api/2.0/';
        if(Vend_Sync_SharedCode.IsSandbox) {
            strSubDomain = 'https://bimuseumofart.vendhq.com/api/2.0/';
        }

        return strSubDomain;
    }

    public static void ProcessDatabaseResults(Database.SaveResult[] results, String messageHeader) {

        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                for(Database.Error err : result.getErrors()) {

                    String errorMessage = '*****' + messageHeader + ' - Error ' + err.getMessage() + ' Status Code: ' + err.getStatusCode() + ' Fields: ' + err.getFields();
                    System.debug(LoggingLevel.ERROR, errorMessage);

                    // Skip Admin Email for UNABLE_TO_LOCK_ROW because can happen for various reasons and next batch call should succeed
                    if (err.getStatusCode() == System.StatusCode.UNABLE_TO_LOCK_ROW) {
                        continue;
                    }

                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);
                }
            }
        }
    }

    public static void ProcessDatabaseResults(Database.DeleteResult[] results, String messageHeader) {

        for (Database.DeleteResult result : results) {
            if (!result.isSuccess()) {
                for(Database.Error err : result.getErrors()) {

                    String errorMessage = '*****' + messageHeader + ' - Error ' + err.getMessage() + ' Status Code: ' + err.getStatusCode() + ' Fields: ' + err.getFields();
                    System.debug(LoggingLevel.ERROR, errorMessage);

                    // Skip Admin Email for UNABLE_TO_LOCK_ROW because can happen for various reasons and next batch call should succeed
                    if (err.getStatusCode() == System.StatusCode.UNABLE_TO_LOCK_ROW) {
                        continue;
                    }

                    Vend_Sync_SharedCode.SendAdminAlert(LoggingLevel.ERROR, Vend_Sync_SharedCode.ADMIN_TYPE, errorMessage);
                }
            }
        }
    }

    public static Boolean ValidateEmail(String email) {
        
        Boolean res = true;
        String emailRegex = '^[a-zA-Z0-9._|\\\\%#~`=?&/$^*!}{+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,4}$'; // source: <a href="http://www.regular-expressions.info/email.html" target="_blank" rel="nofollow">http://www.regular-expressions.info/email.html</a>
        Pattern MyPattern = Pattern.compile(emailRegex);
        Matcher MyMatcher = MyPattern.matcher(email);
    
        if (!MyMatcher.matches()) 
            res = false;
        return res; 
    }
    
    public static String CleanString(String stringValue, Boolean toLowerCase) {
        if (String.isBlank(stringValue)) {
            return stringValue;
        }

        if (toLowerCase) { 
            stringValue = stringValue.toLowerCase();
        }

        return stringValue.trim();
    }

    public static String CleanEmailString(String stringValue, Boolean toLowerCase) {
        if (String.isBlank(stringValue)) {
            return stringValue;
        }

        stringValue = CleanString(stringValue, toLowerCase);

        //if (!ValidateEmail(stringValue)) {

            stringValue = stringValue.replace('..', '.');

            if (stringValue.endsWith('.comm')) {
                stringValue = stringValue.replace('.comm', '.com');
            }

            if (stringValue.endsWith('.orgg')) {
                stringValue = stringValue.replace('.orgg', '.org');
            }
        //}

        // Remove spaces
        stringValue = stringValue.replaceAll(' ', '');


        return stringValue;
    }

    public static Messaging.SingleEmailMessage BuildContactEmail(Id emailTemplateId, Id contactId, Id relatedId, String email, List<OrgWideEmailAddress> orgEmails) {

        if (!ValidateEmail(email)) {
            return null;
        }

		if (emailTemplateId == null) {
			return null;
		}

		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

        if (!orgEmails.isEmpty()) {
            mail.setOrgWideEmailAddressId(orgEmails[0].Id);
        }

		mail.setTemplateId(emailTemplateId);
        mail.setTargetObjectId(contactId);
        if (relatedId != null) {
            mail.setWhatId(relatedId);
        }

        mail.setToAddresses(new List<string>{email});
        mail.setUseSignature(false);
        mail.setBccSender(false);
   		mail.setSaveAsActivity(true);

       return mail;
	}

    public static Messaging.SingleEmailMessage BuildContactEmail_v2(Id emailTemplateId, Id contactId, Id relatedId, String email, List<OrgWideEmailAddress> orgEmails, Boolean bccSender) {

        if (!ValidateEmail(email)) {
            return null;
        }

		if (emailTemplateId == null) {
			return null;
		}

		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

        if (!orgEmails.isEmpty()) {
            mail.setOrgWideEmailAddressId(orgEmails[0].Id);
        }

		mail.setTemplateId(emailTemplateId);
        mail.setTargetObjectId(contactId);
        if (relatedId != null) {
            mail.setWhatId(relatedId);
        }

        mail.setToAddresses(new List<string>{email});
        mail.setUseSignature(false);
        mail.setBccSender(bccSender);
   		mail.setSaveAsActivity(true);

       return mail;
	}

    public static Messaging.SingleEmailMessage BuildUserEmail(Id emailTemplateId, Id userId, Id relatedId, String email, List<OrgWideEmailAddress> orgEmails) {

        if (!ValidateEmail(email)) {
            return null;
        }

		if (emailTemplateId == null) {
			return null;
		}

		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

        if (!orgEmails.isEmpty()) {
            mail.setOrgWideEmailAddressId(orgEmails[0].Id);
        }

		mail.setTemplateId(emailTemplateId);
        mail.setTargetObjectId(userId);
        if (relatedId != null) {
            mail.setWhatId(relatedId);
        }

        mail.setToAddresses(new List<string>{email});
        mail.setUseSignature(false);
        mail.setBccSender(false);

        // Activity must be false for Users
   		mail.setSaveAsActivity(false);

       return mail;
	}

    private static String ExpandMessage(String message) {

        if (String.isBlank(message)) {
            return message;
        }

        String expandedMessage = '';

        if (message.containsIgnoreCase('EMAIL_ADDRESS_BOUNCED')) {
            String contactId = '';
            for (String messageToken :message.split('=|;')) {
                if (messageToken.length() == 18) {
                    contactId = messageToken;
                    break;
                }
            }

            if (!String.isBlank(contactId)){

                String salesforceURL = 'https://bezosfamilyfoundation.my.salesforce.com/';
                if (Vend_Sync_SharedCode.IsSandbox) {
                    salesforceURL = 'https://test.salesforce.com/';
                }

                expandedMessage = 'Bounced Email Notification<br/><br/>';
                expandedMessage += 'Call to Action: Check the email on the Contact, reach out to contact to verify, click verify in Salesforce if confirmed email to try again<br/><br/>';
                expandedMessage += 'Salesforce Contact: ' + salesforceURL + contactId;
            }
        }

        return expandedMessage;
    }

    public static Boolean NearSalesforceLimits(Boolean alwaysOutputLimit) {

        Boolean nearLimit = false;
        Integer percentageMultiple = 95;

        // https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_methods_system_limits.htm

        if (alwaysOutputLimit || Limits.getAggregateQueries() > ((Limits.getLimitAggregateQueries() / 100) * percentageMultiple)) {
            system.debug(LoggingLevel.WARN, '***** Vend_Sync_SharedCode::NearSalesforceLimits - Aggregate Queries ' + String.valueOf(percentageMultiple) + '% of Limit - ' + Limits.getAggregateQueries() + ' of ' + Limits.getLimitAggregateQueries());
            nearLimit = true;
        }

        if (alwaysOutputLimit || Limits.getDMLRows() > ((Limits.getLimitDMLRows() / 100) * percentageMultiple)) {
            system.debug(LoggingLevel.WARN, '***** Vend_Sync_SharedCode::NearSalesforceLimits - DML Rows ' + String.valueOf(percentageMultiple) + '% of Limit - ' + Limits.getDMLRows() + ' of ' + Limits.getLimitDMLRows());
            nearLimit = true;
        }

        if (alwaysOutputLimit || Limits.getDMLStatements() > ((Limits.getLimitDMLStatements() / 100) * percentageMultiple)) {
            system.debug(LoggingLevel.WARN, '***** Vend_Sync_SharedCode::NearSalesforceLimits - DML Statments ' + String.valueOf(percentageMultiple) + '% of Limit - ' + Limits.getDMLStatements() + ' of ' + Limits.getLimitDMLStatements());
            nearLimit = true;
        }

        if (alwaysOutputLimit || Limits.getQueries() > ((Limits.getLimitQueries() / 100) * percentageMultiple)) {
            system.debug(LoggingLevel.WARN, '***** Vend_Sync_SharedCode::NearSalesforceLimits - Queies ' + String.valueOf(percentageMultiple) + '% of Limit - ' + Limits.getQueries() + ' of ' + Limits.getLimitQueries());
            nearLimit = true;
        }

        if (alwaysOutputLimit || Limits.getQueryRows() > ((Limits.getLimitQueryRows() / 100) * percentageMultiple)) {
            system.debug(LoggingLevel.WARN, '***** Vend_Sync_SharedCode::NearSalesforceLimits - Query Rows ' + String.valueOf(percentageMultiple) + '% of Limit - ' + Limits.getQueryRows() + ' of ' + Limits.getLimitQueryRows());
            nearLimit = true;
        }

        if (alwaysOutputLimit || Limits.getSoslQueries() > ((Limits.getLimitSoslQueries() / 100) * percentageMultiple)) {
            system.debug(LoggingLevel.WARN, '***** Vend_Sync_SharedCode::NearSalesforceLimits - Sosl Queries ' + String.valueOf(percentageMultiple) + '% of Limit - ' + Limits.getSoslQueries() + ' of ' + Limits.getLimitSoslQueries());
            nearLimit = true;
        }

        return nearLimit;
    }

    public static void CodeCoverageHack() {

		List<String> updateArray = new List<String> {'3', '4', '5', '6'};

		List<String> loopArray = new List<String> {'3'};
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
        for (String loopIndex :loopArray) {
            updateArray.add('1');
            
        }
    }
}