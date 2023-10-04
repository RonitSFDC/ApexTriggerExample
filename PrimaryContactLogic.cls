trigger PrimaryContact on Contact(after update) {
    
    
    Map<Id, Account> updateAccount = new Map<Id, Account>();
    List<Contact> listOfContacts = new List<Contact>();
    Map<Id, Contact> accIdConMap = new Map<Id, Contact>();
    Set<Id> contactId = new Set<Id>();
    set<Id> processedUpdateConId = new Set<Id>(); // Recursive trigger prevention logic
    if(trigger.isAfter && trigger.isUpdate ) {
        for(Contact con: trigger.new) {
            System.debug('processedUpdateConId : '+ processedUpdateConId);
            if(!processedUpdateConId.contains(con.Id)) {
            if(con.AccountId != null && con.Primary_Contact__c == true) {
                contactId.add(con.Id); // adding contact id to check further with current contact record
                accIdConMap.put(con.AccountId, con);
                System.debug(accIdConMap);
                
            }
            
        }
       
        List<Contact> accountList = [SELECT Id,AccountId, Name, Primary_Contact__c FROM Contact WHERE Primary_Contact__c = true AND AccountID IN :accIdConMap.keySet()];
        for(Contact con1 : accountList ) {
            // to check if current contact id should not same with old contact id
            if(!contactId.contains(con1.Id)) {
                Contact c = new Contact();
                c.Id = con1.Id;
                c.Primary_Contact__c  = false;
                listOfContacts.add(c);
                // Recursive trigger prevention logic
                processedUpdateConId.add(con1.Id);
            }
            
            
            Account acc = new Account();
            acc.id = con.AccountId;
            acc.Primary_Contact_Name__c = accIdConMap.get(con.AccountId).FirstName + ' ' +accIdConMap.get(con.AccountId).LastName;
            updateAccount.put(acc.Id, acc);
        }
        
        try {
            
            DataBase.update(listOfContacts);
            DataBase.update(updateAccount.values());
        }
        catch(Exception e) {
            System.debug('There is a exception');
        }
     }
    }
    
}
