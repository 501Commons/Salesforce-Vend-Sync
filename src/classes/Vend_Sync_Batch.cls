/*
    Copyright (c) 2019, 501Commons.org
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of 501Commons.org nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.
 
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN 
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
    POSSIBILITY OF SUCH DAMAGE.

    Developer Console
      Vend_Sync_Batch.srSyncWebsiteBatch(new List<Id> {'7012I0000014IoB'});

    REST Post Method (steps to call REST Method) - Called from Mass Action Scheduler

        https://workbench.developerforce.com/restExplorer.php
        POST
        URL: /services/data/v46.0/actions/custom/apex/Vend_Sync_Batch

        sr2020 Sandbox
        {
            "inputs" : [ {
                "campaigns" : "701R00000008JS4IAM"
            } ]
        }

        Production
        {
            "inputs" : [ {
                "campaigns" : "7012I0000014IoB"
            } ]
        }

*/

public with sharing class Vend_Sync_Batch {

    public class InvalidParameterValueException extends Exception {}

    @InvocableMethod(label='SR Sync Website' description='Sync data from SR External Website.')
    public static List<Id> srSyncWebsiteBatch(List<Id> campaigns) {

      if (campaigns.isEmpty()) {
        throw new InvalidParameterValueException('Campaign Error - missing active Students Rebuild Campaign');
      }

      // Mass Action is calling this REST method and this REST method wants to call a Webservice which is not allowed by Salesforce.  Apex will throw a System.CalloutException
      //  Links about System.CalloutException    
      //      https://help.salesforce.com/articleView?id=000340086&type=1&mode=1
      //      https://help.salesforce.com/articleView?id=000331332&type=1&mode=1&language=en_US
      //      
      // Workaround is to Batch or Schedule the Apex that will do the callout to the webservice

      // Schedule Batch Job in Flex Queue (can schedule up to 100 jobs)
      String queryExpression = 'SELECT Id FROM Campaign WHERE Id in (\'' + String.join(campaigns, '\',\'') + '\') ORDER BY CreatedDate DESC';

      Vend_Sync_Teams batchRequestSyncTeams = new Vend_Sync_Teams();
      batchRequestSyncTeams.query = queryExpression;
      Database.executeBatch(batchRequestSyncTeams);

      Vend_Sync_Results batchRequestSyncResults = new Vend_Sync_Results();
      batchRequestSyncResults.query = queryExpression;
      Database.executeBatch(batchRequestSyncResults);

      Vend_Sync_DeletedTeams batchRequestSyncDeletedTeams = new Vend_Sync_DeletedTeams();
      batchRequestSyncDeletedTeams.query = queryExpression;
      Database.executeBatch(batchRequestSyncDeletedTeams);

      Vend_Sync_DeletedResults batchRequestSyncDeletedResults = new Vend_Sync_DeletedResults();
      batchRequestSyncDeletedResults.query = queryExpression;
      Database.executeBatch(batchRequestSyncDeletedResults);

      return campaigns;
    }
}