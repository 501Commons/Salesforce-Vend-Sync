// Run Code FROM Developer Console
//  1) Debug -> Open Execute Anonymous Window
//  2) paste code
/*
    Vend_Sync_Sales.srSyncWebsiteResults( new List<Id> { '701R00000008JS4' });
*/
//  3) click Execute

global class Vend_Sync_Sales implements Database.Batchable<sObject>, Database.AllowsCallouts { 

    global String query;

    global Database.querylocator start(Database.BatchableContext BC) {
        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Sales::start - query: ' + query);
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext info, List<sObject> scope) {

        System.debug(LoggingLevel.DEBUG, '***** Vend_Sync_Sales::execute - scope: ' + scope);
    }

    global void finish(Database.BatchableContext info) {
    }
}