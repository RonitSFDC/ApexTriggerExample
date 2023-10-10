//To fetch records from three related custom objects and store the details in a CSV file using Apex in Salesforce, you'll need to follow these steps:
public class RelatedCustomObjectDataToCSV {
    public static void exportToCSV() {
        // Query records from Parent Object
        List<ParentObject__c> parentRecords = [SELECT Id, Name, (SELECT Id, Name FROM ChildObjects__r) FROM ParentObject__c];

        // Combine records from all custom objects
        List<String> csvLines = new List<String>();
        csvLines.add('ParentName,ChildName');

        for (ParentObject__c parent : parentRecords) {
            for (ChildObject__c child : parent.ChildObjects__r) {
                String csvLine = parent.Name + ',' + child.Name;
                csvLines.add(csvLine);
            }
        }

        // Create and save the CSV file
        String csvContent = String.join(csvLines, '\n');
        Blob csvBlob = Blob.valueOf(csvContent);

        Attachment attachment = new Attachment();
        attachment.Body = csvBlob;
        attachment.Name = 'RelatedObjectData.csv';
        attachment.ParentId = 'Your_Record_Id'; // Specify where you want to attach the file
        insert attachment;
    }
}
