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
      Vend_Sync_Batch.vendSyncBatch();

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

    @InvocableMethod(label='Vend Sync Batch' description='Vend Sync data from Vend REST API into Salesforce.')
    public static void vendSyncBatch() {

      Vend_Sync_Object syncCustomerRecords = new Vend_Sync_Object();
      syncCustomerRecords.vendApiType = Vend_Sync_Object.VendApiTypes.customers;
      ID jobIdCustomers = System.enqueueJob(syncCustomerRecords);
      System.debug(LoggingLevel.DEBUG, '****Vend_Sync_Batch:vendSyncBatch Customers jobId: ' + jobIdCustomers);

      Vend_Sync_Object syncProductRecords = new Vend_Sync_Object();
      syncProductRecords.vendApiType = Vend_Sync_Object.VendApiTypes.products;
      ID jobIdProducts = System.enqueueJob(syncProductRecords);
      System.debug(LoggingLevel.DEBUG, '****Vend_Sync_Batch:vendSyncBatch Products jobId: ' + jobIdProducts);
    
      Vend_Sync_Object syncSaleRecords = new Vend_Sync_Object();
      syncSaleRecords.vendApiType = Vend_Sync_Object.VendApiTypes.sales;
      ID jobIdSales = System.enqueueJob(syncSaleRecords);
      System.debug(LoggingLevel.DEBUG, '****Vend_Sync_Batch:vendSyncBatch Sales jobId: ' + jobIdSales);
    }
}