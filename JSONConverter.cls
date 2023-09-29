List<Test_Integration_Log__c> errorList = [SELECT id, Error_Log__c FROM Test_Integration_Log__c];

List<Object> consent = new List<Object>();

for(Test_Integration_Log__c item : errorList) {
    if(item.Error_Log__c != null) {
        
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(item.Error_Log__c);
        System.debug(jsonMap);
        System.debug(jsonMap.get('consent'));
        List<Object> data = (List<Object>) jsonMap.get('consent');
        system.debug(data[0]);
        consent.add(data[0]);
    }
}
Map<String, List<Object>> result = new Map<String, List<Object>>();
result.put('consent', consent);

String resultJson = JSON.serialize(result);
System.debug(resultJson);
