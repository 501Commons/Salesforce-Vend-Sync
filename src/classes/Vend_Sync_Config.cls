// Run Code FROM Developer Console
//  1) Debug -> Open Execute Anonymous Window
//  2) paste code
/*
    Vend_Sync_Config.srSyncWebsiteConfig( new List<Id> { '701R00000008JS4' });
*/
//  3) click Execute

public with sharing class Vend_Sync_Config {

    public class InvalidParameterValueException extends Exception {}

    public static void srSyncWebsiteConfig(List<Id> campaignIds) {

		if (campaignIds.isEmpty()) {
			throw new InvalidParameterValueException('Campaign Error - missing active Students Rebuild Campaig Ids');
		}

		List<Campaign> campaigns = [select Id, Name, IsActive, StartDate, SR_Number_of_Items__c, SR_Number_of_Teams__c, SR_Number_of_Young_People__c from Campaign WHERE Id in :campaignIds order by CreatedDate desc];
		if (campaigns.isEmpty()) {
			throw new InvalidParameterValueException('Campaign Error - missing active Students Rebuild Campaign');
		}

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        request.setEndpoint('https://' + Vend_Sync_SharedCode.GetExternalWebsiteSubdomain() + '.studentsrebuild.org/sync/config');

        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');

        String config = Vend_Sync_Config.getConfig();

        // Example Challenge Format
        //  {"id": "asdf-asdf-asdf-asd","name": "A New Challenge","active": true,"startDate": "2019-06-11T17:14:05.000+0000"},
        //  {"id": "7010G000000vtMkQAI","name": "Students Rebuild: Facing Difference Challenge","active": false,"startDate": "2017-09-19T23:05:16.000+0000"}
        String configChallenge = '{"id": "VALUE_ID","name": "VALUE_NAME","active": VALUE_ACTIVE,"startDate": VALUE_STARTDATE}';
        String challenges = '';
        for (Campaign campaign :campaigns) {

            if (!String.isBlank(challenges)) {
                challenges += ',';
            }

            challenges += configChallenge.replace('VALUE_ID', campaign.Id);
            challenges = challenges.replace('VALUE_NAME', campaign.Name);
            challenges = challenges.replace('VALUE_ACTIVE', String.valueOf(campaign.IsActive));
            challenges = challenges.replace('VALUE_STARTDATE', campaign.StartDate.format());
        }

        system.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Config::srSyncConfig challenges: ' + challenges);

        config = config.replace('VALUE_CHALLENGES', challenges);

        Vend_Sync_Config.TestJSON(config);

        request.setBody(config);

        HttpResponse response = http.send(request);

        if (response.getStatusCode() != 200) {
            System.debug(LoggingLevel.ERROR, '*****Vend_Sync_Config::srSyncConfig post failed with response: ' + response.getBody());
            return;
        }

        Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        if (results <> null) {
            system.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Config::srSyncConfig post response: ' + results);
            return;
        }
    }

    private static String getConfig() {

        String config = '{"token":"' + Vend_Sync_SharedCode.GetExternalWebsiteToken() + '"},' +
            'config: {\n' +
                ' "challenges": [' +
                'VALUE_CHALLENGES' +
// Example Challenge Format
//                    '{"id": "asdf-asdf-asdf-asd","name": "A New Challenge","active": true,"startDate": "2019-06-11T17:14:05.000+0000"},' +
//                    '{"id": "7010G000000vtMkQAI","name": "Students Rebuild: Facing Difference Challenge","active": false,"startDate": "2017-09-19T23:05:16.000+0000"}' +
                '],' +

/*
                ' "ageGroups": ["0-5","6-11","12-14","15-17","18+"],\n' +
                ' "orgTypesMap":' +
                '{' +
                    '"Other": ["Other"],' +
                    '"Education/School": ["College/University","Early childhood 0-5","Elementary","High School","Jr. High/Middle","Other Education/School","Out of school program","School District","School Library"],' +
                    '"Individual/Family": ["Individual/Family"],' +
                    '"Community-Based Organization": ["Faith-based","Library","Museum","Other CBO","Service or volunteer club","Youth and Families"]' +
                '},\n' +
                ' "howDidYouHearOptions": [' +
                    '"At an Event",' +
                    '"Global Nomads Group",' +
                    '"The Nature Conservancy",' +
                    '"Postcard/Mailing",' +
                    '"Social Media",' +
                    '"Someone I Know",' +
                    '"Students Rebuild Newsletter",' +
                    '"Other"' +
                '],\n' +
                ' "contactRoleOptions": [' +
                    '"Student",' +
                    '"Teacher / Educator",' +
                    '"Youth Activities Coordinator",' +
                    '"Parent",' +
                    '"Other"' +
                '],\n' +
                ' "leaderAges": [' +
                    '"12 and Under",' +
                    '"13-18",' +
                    '"19-24",' +
                    '"25-44",' +
                    '"45-64",' +
                    '"65 and Over"' +
                '],\n' +
                ' "leaderRoles": [' +
                    '"Student",' +
                    '"Teacher / Educator",' +
                    '"Youth Activities Coordinator",' +
                    '"Parent",' +
                    '"Other"' +
                '],\n' +
*/
            '}' +
        '}';

        return config;
    }

    private static void TestJSON(String JSONValue) {

        Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(JSONValue);
        if (results == null) {
            return;
        }

        List<Object> config = (List<Object>) results.get('config');
        if (config == null  || config.size() <= 0) {
            return;
        }

        for (Object result: config) {

            String JSONData = JSON.serialize(result);
            Map<String, Object> srData = (Map<String, Object>)JSON.deserializeUntyped(JSONData);

            System.debug(LoggingLevel.DEBUG, '*****Vend_Sync_Config::TestJSON - srData: ' + srData);
        }

    }
}