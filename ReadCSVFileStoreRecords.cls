To read a CSV file and store its data as records in Salesforce using Apex, you can follow these steps:
public class CSVReader {

    public static void readCSVFile(String csvBody) {
        List<String> csvLines = csvBody.split('\n');
        List<MyCustomObject__c> recordsToInsert = new List<MyCustomObject__c>();

        for (Integer i = 1; i < csvLines.size(); i++) {
            List<String> csvValues = csvLines[i].split(',');

            if (csvValues.size() == 3) { // Assuming 3 fields in the CSV (adjust as needed)
                MyCustomObject__c record = new MyCustomObject__c(
                    Field1__c = csvValues[0],
                    Field2__c = csvValues[1],
                    Field3__c = csvValues[2]
                );
                recordsToInsert.add(record);
            }
        }

        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }
    }
}


public with sharing class CSVFileReader {
    @AuraEnabled(cacheable=true)
    public static List<String> readCSVFile(String csvContent) {
        List<String> csvLines = csvContent.split('\n');
        return csvLines;
    }
}
