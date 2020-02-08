// Run Code FROM Developer Console
//  1) Debug -> Open Execute Anonymous Window
//  2) paste code
/*
    Vend Sync: Hunger Challenge (Production)

    Developer Console (steps to call method directly)

        Vend_Sync_Products.srSyncWebsiteTeams( new List<Id> { '7012I0000014IoB' });

*/
//  3) click Execute

global class Vend_Sync_Products implements Database.Batchable<sObject>, Database.AllowsCallouts { 

    global String query;

    global Database.querylocator start(Database.BatchableContext BC) {
        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Products::start - query: ' + query);
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext info, List<sObject> scope) {

        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Products::execute - scope: ' + scope);
    }

    global void finish(Database.BatchableContext info) {
    }
}