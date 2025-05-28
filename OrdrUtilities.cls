/* Modification Log:
* -----------------------------------------------------------------------------------------------------------------------------------------
* Date                Modified By           Description
* -----------------------------------------------------------------------------------------------------------------------------------------
* 09-Aug-2017         Sandip                15237 : Added logic to create 16 digit location Id
* 30-Nov-2022         Jay Thiru             FNDA-27381: Added condition so that a child item only inherits its top offer's term value
*                                           if there is no term value already set for the child item     
* 16-Dec-2022         Sireesha              FNDA-27780 : Getting Book appointment error on order summary page even appointment is not required.
*                                           Fixed deserialization issue with onsite contact JSON. 
* 31-Jul-2023         Tejaswini             NTSII-163 : Changes as per v2 json upgrade, replaced vlocity_cmt__JSONAttribute__c with new schema fields
* 7-Sep-2023          Gaurang Soni          FNDA-38984: Added logic to persist the values for selected Attributes in dest json  
* 06-Oct-2023         Shekhar Kumar         FNDA-40103: Removed saveDecompMsg() message logged to the Webservice Integration Error Log.
* 4/3/2024            Vishal Rathod         FNDA-42409: Update to exclude updating download speed and upload speed on order item attributes
******************************************************************************************************************************************/
public class OrdrUtilities {
    
    public static Map<String,DateTime> orderIdDateTimeMap=new Map<String,DateTime>();
    public static Map<String,DateTime> orderIdDateTimeMapFromHist=new Map<String,DateTime>();
    
    public static Set<String> orderTnIdSet=new Set<String>();
    public static Boolean useTNSessionCache=true;
    public static Boolean useAuditFlag=false;
    public static List<webservice_integration_error_log__c> errList=new List<webservice_integration_error_log__c>();
    public static Boolean ignoreCharNameForAmend=true;
    public static String prodSpecId=null;
    public static Map<String, vlocity_cmt__CatalogProductRelationship__c> contractableProductsMap;
    public static final String PARTNER_COMMUNITY_LICENSE = 'Partner Community'; //LOTR-75    
    public static final String DEFAULTCHANNEL = 'Default';
    public static Integer numberOfWorkRequest =0;  
    public static User user;                // OCA-1287
    public static List<Profile_Distribution_Channel_Mapping__mdt> distributionChannels;     // OCA-1287
    public static Application_General_Data__C appData;      // OCA-1287

    //List of Attributes to persist it's value 
    public static final List<String> ATTR_TO_PERSIST = new List<String>{
        'Package ID',
        'Offering ID',
        'Package Name',
        'Download speed',
        'Upload speed'
    };

    //Start NCA-70
    private static Map<Id,vlocity_cmt__Attribute__c> customerFacingAttrMap= new Map<Id,vlocity_cmt__Attribute__c>();
    static{
        customerFacingAttrMap  =new Map<Id,vlocity_cmt__Attribute__c>([SELECT Id, Name, orderMgmtId__c FROM vlocity_cmt__Attribute__c where Show_Customer_Facing_Mat__c =true]);
    }
    //END Changes NCA-70
    
    public static String getDistributionChannel(Boolean isDistributionChannelId)
    {
        return getDistributionChannel(isDistributionChannelId, false);
    }
    /*******************************************************************************************************
    * @description: get distribution channel ID / Name mapped as per the Profile of the User
    * @return return distribution channel ID / Name
    * @param isDistributionChannelId returns channel id when set to true or return Channel name when set to false
    *
    */
    public static String getDistributionChannel(Boolean isDistributionChannelId, Boolean cacheKey){
        String distributionChannel = '';
        String defaultDistributionChannel ='';
        String userId = UserInfo.getUserId();
        Set<String> profileName = new Set<String>{DEFAULTCHANNEL};
        if(user == null){   // OCA-1287     
            user = [select Profile.Name, FederationIdentifier, License_Type__c, Group_Membership__c  from User where Id = :userId LIMIT 1];
            profileName.add(user.Profile.Name);
        }
        //get default distributionChannel, if the above fail to get the distributionChannel
        if(distributionChannels == null){
            distributionChannels = [Select Label, Distribution_Channel__c,
                                    NC_Distribution_Channel_Id__c from Profile_Distribution_Channel_Mapping__mdt
                                    where Label IN:profileName OR Label =: user.License_Type__c];
        }
        if(distributionChannels.size()>0){
            for(Profile_Distribution_Channel_Mapping__mdt dsChannel :distributionChannels){
                if(dsChannel.Label.equalsIgnoreCase(user.Profile.Name) || dsChannel.Label.equalsIgnoreCase(user.License_Type__c)){
                    if(isDistributionChannelId){
                        distributionChannel = dsChannel.NC_Distribution_Channel_Id__c;
                    }else{
                        distributionChannel = dsChannel.Distribution_Channel__c;
                    }
                }
                //get default channel name/Id if there is no record for the current user Profile in metadata
                if(dsChannel.Label.equalsIgnoreCase(DEFAULTCHANNEL)){   
                    if(isDistributionChannelId){
                        defaultDistributionChannel = dsChannel.NC_Distribution_Channel_Id__c;
                    }else {
                        defaultDistributionChannel = dsChannel.Distribution_Channel__c;
                    }
                }
            }
            if(String.isBlank(distributionChannel)){
                distributionChannel = defaultDistributionChannel;
            }
        }
        
        //OPI-81/OPI-76 START
        //get distributionChannel for external user from CMS         
        if(user.License_Type__c.equals(PARTNER_COMMUNITY_LICENSE) && String.isNotBlank(user.FederationIdentifier) )  //LOTR-75      
        {
            try{
                String key = 'keyValJson_'+user.FederationIdentifier;
                if(appData == null){
                    appData =  [SELECT Value__c FROM Application_General_Data__c WHERE Key__c = :key ORDER BY createddate DESC LIMIT 1];
                }
                if (appData != null && String.isNotBlank(appData.Value__c)){
                    Map<String, Object> appDataValue = (Map<String, Object>)Json.deserializeUntyped(appData.Value__c);
                    if(appDataValue.get('currentChannelOutletID') != null){
                        String outletID = String.valueOf(appDataValue.get('currentChannelOutletID'));
                        if(String.isNotBlank(outletID))
                        {
                            if(cacheKey){
                                return outletID;
                            }
                            else
                            {
                                return distributionChannel+'_CURRENTCHANNELOUTLETID_'+outletID;
                            }
                        }
                        
                    }
                }
            }Catch (Exception e){}//Invalid JSON Data or No appData. We will return the default  Distribution Channel.
        }
        //get distributionChannel for Internal User 
        else if(String.isNotBlank(user.Group_Membership__c))
        {
            if(cacheKey){
                return user.Group_Membership__c;
            }
            else
            {
                return distributionChannel+'_GROUPNAME_'+user.Group_Membership__c;
            }
        }
        //OPI-81/OPI-76 END
        
        return distributionChannel;
    }
    /*
    Modified By - Sandip 09 Aug 2017 - Defect 15237 - Sandip - Added logic to create 16 digit location Id
    This method used to generate 18 digit unique Id using service location, if service location is balnk then used current timestamp to generate unique Id.
    Service location would be converted to hashcode and then hex values. Logic will take first and last 8 characters from the genrated hex code and prefix 'S-'
    This is interim solution untill permanat solution ready. Permanent solution might be to intgrate LocationPDF to create service address and get locationId. 
    */
    public static String generateUniqueHashCode(String address,String province,String city,String postalCode,String Country) {
        String concatenatedStr='';
        if(String.isNotBlank(address)){
            concatenatedStr=concatenatedStr+address;
        }
        if(String.isNotBlank(province)){
            concatenatedStr=concatenatedStr+province;
        }
        if(String.isNotBlank(city)){
            concatenatedStr=concatenatedStr+city;
        }
        if(String.isNotBlank(Country)){
            concatenatedStr=concatenatedStr+Country;
        }
        if(String.isNotBlank(postalCode)){
            concatenatedStr=concatenatedStr+postalCode;
        }
        /* Defect 15237 - Sandip - Added logic to create 16 digit Id */
        String hexDigest;
        if(String.isNotBlank(concatenatedStr)){
            concatenatedStr = concatenatedStr.toUpperCase();
            String hash = String.valueOf(concatenatedStr.hashCode());
            hexDigest = EncodingUtil.convertToHex(Blob.valueOf(hash));
            //system.debug('@@@hexDigest1' + hexDigest);
        }else{
            hexDigest = generateUniqueHashCode();
            //system.debug('@@@hexDigest2' + hexDigest);
        }
        String uniqueId = 'SF';
        if (hexDigest.length() <= 16) {
            uniqueId = uniqueId+hexDigest;
        } else {
            String firstEightchar = hexDigest.SubString(0,8);  
            String lastEightchar = hexDigest.SubString(hexDigest.length()-8);
            uniqueId = uniqueId+firstEightchar+lastEightchar;
        }
        //system.debug('@@@uniqueId' + uniqueId);
        return uniqueId;
        // End 15237
    }
    
    public static String generateUniqueHashCode() {
        String hashString = String.valueOf(Datetime.now().formatGMT('yyyy-MM-dd HH:mm:ss.SSS'));
        Blob hash = Crypto.generateDigest('MD5', Blob.valueOf(hashString));
        String hexDigest = EncodingUtil.convertToHex(hash);
       // system.debug('@@@dateHex' + hexDigest);
        return hexDigest;
    }
    
    /*
    * @description: Generate a comma separated fields to mimic the popular Select * SQL syntax.
    */    
    public static String commaSeparatedFields(String objectName, List<String> relatedObjectNames) {
        
        String query = '';
        Map<String, Schema.SObjectField> objectFields = Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        // Grab the fields from the describe method and append them to the queryString one by one.
        for(String s : objectFields.keySet()) {
            query += s + ', ';
        }
        
        if (relatedObjectNames != null) {
            for (String obj : relatedObjectNames) {
                objectFields = Schema.getGlobalDescribe().get(obj).getDescribe().fields.getMap();
                for(String s : objectFields.keySet()) {
                    query += obj + '.' + s + ', ';
                }            
            }
        }
        
        // Strip off the last comma.
        query = query.removeEnd(', ');
        
        return query;
    }
    
    /*
    * @description: Return the Telus Id if populated, otherwise the SFDC user object id.
    */    
    public static String getCurrentUserTelusId() {
        String userId = UserInfo.getUserId();
        User user = [select Team_TELUS_ID__c from User where Id = :userId LIMIT 1];
        return String.isBlank(user.Team_TELUS_ID__c) ? userId : user.Team_TELUS_ID__c;
    }
    
    public static Boolean isSuperUser() {
        String userId = UserInfo.getUserId();
        User user = [select CPQ_Super_User_Access__c from User where Id = :userId LIMIT 1];
        return user.CPQ_Super_User_Access__c;
    }
    
    /*common function to construct CharacteristicValue
    */
    
    public static TpCommonBaseV3.CharacteristicValue constructCharacteristicValue(String name, String value) {
        return constructCharacteristicValue(name, new List<String>{value});
    }
    
    public static TpCommonBaseV3.CharacteristicValue constructCharacteristicValue(String name, List<String> values) {
        TpCommonBaseV3.CharacteristicValue characteristicValue = new TpCommonBaseV3.CharacteristicValue();
        TpCommonBaseV3.Characteristic characteristic = new TpCommonBaseV3.Characteristic();
        
        characteristic.Name = name;
        characteristicValue.Characteristic = characteristic;
        characteristicValue.Value = values;
        
        return characteristicValue;
    }     
    
    public static OrdrWsCancelCustomerOrder.CancelCustomerOrderSOAPPort updateSoapPort
        (OrdrWsCancelCustomerOrder.CancelCustomerOrderSOAPPort svcPort, String endpoint)
    {          
        // S-681905 6/23/21 Ravina - Started
        String CallType = 'KONG_CancelCustomerOrder';
        String namedCredKong = NamedCredential_Utility.getEndPointURL(CallType);
        String endpoint_x = namedCredKong;    
        // S-681905 6/23/21 Ravina - Ended
        if (!svcPort.endpoint_x.startsWith(OrdrConstants.ENDPOINT_XML_GATEWAY_SYMBOL)) 
        {
           
            // S-681905 6/23/21 Ravina - Started
            ExternalServiceConfigurationImpl.AuthResponse authResponse = new ExternalServiceConfigurationImpl().getBearerTokenAndServiceURLs(
                'KONG_AUTH', 'KONG_CancelCustomerOrder', 'KONG', true);
            svcPort.inputHttpHeaders_x = new Map<String, String>();
            //svcPort.inputHttpHeaders_x.put(OrdrConstants.AUTHORIZATION, OrdrConstants.BASIC + encodedUserNameAndPassword);
            svcPort.inputHttpHeaders_x.put(AddressConstants.AUTHORIZATION, String.format(AddressConstants.BEARER_TOKEN, new List<String>{
                authResponse.access_token
                    }));
            svcPort.endpoint_x = endpoint_x;
           // System.debug('NCarson endpoint_x : ' + svcPort.endpoint_x);
            // S-681905 6/23/21 Ravina - Ended
        } 
        else 
        {
           
            svcPort.clientCertName_x = OrdrConstants.SDF_CERT_NAME;
        }
        
        
        return svcPort;
        
    }   
    
    public static String rollupActionForOrderItem(OrderItem inOrderItem){
        if(String.isNotBlank(inOrderItem.vlocity_cmt__ProvisioningStatus__c) && (inOrderItem.vlocity_cmt__ProvisioningStatus__c.equals(OrdrConstantS.MACD_STATUS_CHANGED)||inOrderItem.vlocity_cmt__ProvisioningStatus__c.equals(OrdrConstantS.MACD_STATUS_DELETED))){
            return inOrderItem.vlocity_cmt__ProvisioningStatus__c;
        }
        
        List<OrderItem> orderItemList=[select vlocity_cmt__LineNumber__c,vlocity_cmt__ProvisioningStatus__c from orderitem where orderid=: inOrderItem.orderid];
        for(OrderItem orderItemObj:orderItemList){
            String orderItemObjLineNumber=orderItemObj.vlocity_cmt__LineNumber__c;
            String inOrderItemLineNumber=inOrderItem.vlocity_cmt__LineNumber__c;
            if(String.isNotBlank(orderItemObjLineNumber) && String.isNotBlank(inOrderItemLineNumber) && !orderItemObjLineNumber.equals(inOrderItemLineNumber)){
                if(orderItemObjLineNumber.startsWith(inOrderItemLineNumber) && orderItemObjLineNumber.contains(inOrderItemLineNumber)){
                    String orderLineProvStatus=orderItemObj.vlocity_cmt__ProvisioningStatus__c;
                    if(String.isNotBlank(orderLineProvStatus)){
                        if(orderLineProvStatus.equals(OrdrConstantS.MACD_STATUS_NEW)||orderLineProvStatus.equals(OrdrConstantS.MACD_STATUS_CHANGED)||orderLineProvStatus.equals(OrdrConstantS.MACD_STATUS_DELETED)){
                            return OrdrConstantS.MACD_STATUS_CHANGED;
                        }
                    }
                }
            }
        }
        return OrdrConstantS.MACD_STATUS_NONE;
    }
    
    /*build address section of the PCOF and CGTA payload
*/
    public static TpCommonUrbanPropertyAddressV3.UrbanPropertyAddress constructAddress(Map<String, Object> inputMap) {
        TpCommonUrbanPropertyAddressV3.UrbanPropertyAddress address = new TpCommonUrbanPropertyAddressV3.UrbanPropertyAddress();  
        List<TpCommonBaseV3.CharacteristicValue> characteristicValues = new List<TpCommonBaseV3.CharacteristicValue>();
        Map<String, String> mandatoryFields = new Map<String, String>();
        mandatoryFields.put(OrdrConstants.LOCATION_ID, OrdrConstants.LOCATION_ID);
        mandatoryFields.put(OrdrConstants.ADDRESS_TYPE, OrdrConstants.ADDRESS_TYPE);
        mandatoryFields.put(OrdrConstants.ADDR_PROVINCE_CODE, OrdrConstants.ADDR_PROVINCE_CODE);
        mandatoryFields.put(OrdrConstants.IS_ILEC, OrdrConstants.IS_ILEC);
        
        //FMS Id is optional (non-ILEC support) as per PCOF IA
        if (inputMap.containsKey(OrdrConstants.FMS_ID) && inputMap.get(OrdrConstants.FMS_ID) != null) {
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.FMS_ID, (String)inputMap.get(OrdrConstants.FMS_ID)));
        } 
        //Location Id is mandatory as per PCOF IA    
        if (inputMap.containsKey(OrdrConstants.LOCATION_ID) && inputMap.get(OrdrConstants.LOCATION_ID) != null) {
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.LOCATION_ID, (String)inputMap.get(OrdrConstants.LOCATION_ID)));
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.LOCATION_KEY, (String)inputMap.get(OrdrConstants.LOCATION_ID)));
            mandatoryFields.remove(OrdrConstants.LOCATION_ID);
        } 
        //Is ILEC Address is mandatory as per PCOF IA    
        if (inputMap.containsKey(OrdrConstants.IS_ILEC) && inputMap.get(OrdrConstants.IS_ILEC) != null) {
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.IS_ILEC, (String)inputMap.get(OrdrConstants.IS_ILEC)));
            mandatoryFields.remove(OrdrConstants.IS_ILEC);
        } 
        //Address Type is mandatory as per PCOF IA
        String addressType = '';
        if (inputMap.containsKey(OrdrConstants.ADDRESS_TYPE) && inputMap.get(OrdrConstants.ADDRESS_TYPE) != null) {
            addressType = (String)inputMap.get(OrdrConstants.ADDRESS_TYPE);
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDRESS_TYPE, addressType));
            mandatoryFields.remove(OrdrConstants.ADDRESS_TYPE);
        } 
        if (inputMap.containsKey(OrdrConstants.ADDR_COUNTRY_CODE) && inputMap.get(OrdrConstants.ADDR_COUNTRY_CODE) != null) {
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_COUNTRY_CODE, (String)inputMap.get(OrdrConstants.ADDR_COUNTRY_CODE)));
        }
        //Province Code is mandatory as per PCOF IA
        if (inputMap.containsKey(OrdrConstants.ADDR_PROVINCE_CODE) && inputMap.get(OrdrConstants.ADDR_PROVINCE_CODE) != null) {
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_PROVINCE_CODE, (String)inputMap.get(OrdrConstants.ADDR_PROVINCE_CODE)));
            mandatoryFields.remove(OrdrConstants.ADDR_PROVINCE_CODE);
        } 
        //Postal Code is optional for all address type 
        if (inputMap.containsKey(OrdrConstants.ADDR_POSTAL_CODE) && inputMap.get(OrdrConstants.ADDR_POSTAL_CODE) != null) {
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_POSTAL_CODE, (String)inputMap.get(OrdrConstants.ADDR_POSTAL_CODE)));
        } 
        // Rate Band is option for all address type BP1-336
        if (inputMap.containsKey(OrdrConstants.ADDR_RATE_BAND) && inputMap.get(OrdrConstants.ADDR_RATE_BAND) != null) {
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_RATE_BAND, (String)inputMap.get(OrdrConstants.ADDR_RATE_BAND)));
        } 
        // Forborne is option for all address type BP1-336
        if (inputMap.containsKey(OrdrConstants.ADDR_FORBORNE) && inputMap.get(OrdrConstants.ADDR_FORBORNE) != null) {
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_FORBORNE, (String)inputMap.get(OrdrConstants.ADDR_FORBORNE)));
        } 
        if (inputMap.containsKey(OrdrConstants.ADDR_ISFIFA) && inputMap.get(OrdrConstants.ADDR_ISFIFA) != null) {
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_ISFIFA, (String)inputMap.get(OrdrConstants.ADDR_ISFIFA)));
        } 
        if (inputMap.containsKey(OrdrConstants.ADDR_ISDROPREADY) && inputMap.get(OrdrConstants.ADDR_ISDROPREADY) != null) {
            characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_ISDROPREADY, (String)inputMap.get(OrdrConstants.ADDR_ISDROPREADY)));
        } 
        
        
        //addressType = Standard
        if (addressType == OrdrConstants.ADDRESS_TYPE_STANDARD) {
            mandatoryFields.put(OrdrConstants.ADDR_MUNICIPALITY, OrdrConstants.ADDR_MUNICIPALITY);
            mandatoryFields.put(OrdrConstants.ADDR_STREET_NAME, OrdrConstants.ADDR_STREET_NAME);
            
            //Municipality is mandatory for Standard address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_MUNICIPALITY) && inputMap.get(OrdrConstants.ADDR_MUNICIPALITY) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_MUNICIPALITY, (String)inputMap.get(OrdrConstants.ADDR_MUNICIPALITY)));
                mandatoryFields.remove(OrdrConstants.ADDR_MUNICIPALITY);
            } 
            //Street Direction is optional for Standard address type 
            if (inputMap.containsKey(OrdrConstants.ADDR_STREET_DIRECTION) && inputMap.get(OrdrConstants.ADDR_STREET_DIRECTION) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_STREET_DIRECTION, (String)inputMap.get(OrdrConstants.ADDR_STREET_DIRECTION)));
            } 
            //Street Type Code is optional for Standard address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_STREET_TYPE) && inputMap.get(OrdrConstants.ADDR_STREET_TYPE) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_STREET_TYPE, (String)inputMap.get(OrdrConstants.ADDR_STREET_TYPE)));
            } 
            //Street Name is mandatory for Standard address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_STREET_NAME) && inputMap.get(OrdrConstants.ADDR_STREET_NAME) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_STREET_NAME, (String)inputMap.get(OrdrConstants.ADDR_STREET_NAME)));
                mandatoryFields.remove(OrdrConstants.ADDR_STREET_NAME);
            } 
            //Street Number is optional for Standard address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_STREET_NUMBER) && inputMap.get(OrdrConstants.ADDR_STREET_NUMBER) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_STREET_NUMBER, (String)inputMap.get(OrdrConstants.ADDR_STREET_NUMBER)));
            } 
            //Unit Number is optional for Standard address type 
            if (inputMap.containsKey(OrdrConstants.ADDR_UNIT_NUMBER) && inputMap.get(OrdrConstants.ADDR_UNIT_NUMBER) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_UNIT_NUMBER, (String)inputMap.get(OrdrConstants.ADDR_UNIT_NUMBER)));
            } 
        }
        else {
            //Municipality is optional for all types other than Standard address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_MUNICIPALITY) && inputMap.get(OrdrConstants.ADDR_MUNICIPALITY) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_MUNICIPALITY, (String)inputMap.get(OrdrConstants.ADDR_MUNICIPALITY)));
            } 
        }
        
        //addressType = LotBlockPlan
        if (addressType == OrdrConstants.ADDRESS_TYPE_LOT_BLOCK_PLAN) {
            mandatoryFields.put(OrdrConstants.ADDR_LOT, OrdrConstants.ADDR_LOT);
            mandatoryFields.put(OrdrConstants.ADDR_BLOCK, OrdrConstants.ADDR_BLOCK);
            mandatoryFields.put(OrdrConstants.ADDR_PLAN, OrdrConstants.ADDR_PLAN);
            
            //Lot is mandatory for LotBlockPlan address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_LOT) && inputMap.get(OrdrConstants.ADDR_LOT) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_LOT, (String)inputMap.get(OrdrConstants.ADDR_LOT)));
                mandatoryFields.remove(OrdrConstants.ADDR_LOT);
            } 
            //Block is mandatory for LotBlockPlan address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_BLOCK) && inputMap.get(OrdrConstants.ADDR_BLOCK) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_BLOCK, (String)inputMap.get(OrdrConstants.ADDR_BLOCK)));
                mandatoryFields.remove(OrdrConstants.ADDR_BLOCK);
            } 
            //Plan is mandatory for LotBlockPlan address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_PLAN) && inputMap.get(OrdrConstants.ADDR_PLAN) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_PLAN, (String)inputMap.get(OrdrConstants.ADDR_PLAN)));
                mandatoryFields.remove(OrdrConstants.ADDR_PLAN);
            } 
        }
        
        //addressType = LegalLandDescription
        if (addressType == OrdrConstants.ADDRESS_TYPE_LEGAL_LAND_DESC) {
            mandatoryFields.put(OrdrConstants.ADDR_QUARTER, OrdrConstants.ADDR_QUARTER);
            mandatoryFields.put(OrdrConstants.ADDR_SECTION, OrdrConstants.ADDR_SECTION);
            mandatoryFields.put(OrdrConstants.ADDR_TOWNSHIP, OrdrConstants.ADDR_TOWNSHIP);
            mandatoryFields.put(OrdrConstants.ADDR_RANGE, OrdrConstants.ADDR_RANGE);
            mandatoryFields.put(OrdrConstants.ADDR_MERIDIAN, OrdrConstants.ADDR_MERIDIAN);
            
            //Quarter is mandatory for LegalLandDescription address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_QUARTER) && inputMap.get(OrdrConstants.ADDR_QUARTER) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_QUARTER, (String)inputMap.get(OrdrConstants.ADDR_QUARTER)));
                mandatoryFields.remove(OrdrConstants.ADDR_QUARTER);
            } 
            //Section is mandatory for LegalLandDescription address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_SECTION) && inputMap.get(OrdrConstants.ADDR_SECTION) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_SECTION, (String)inputMap.get(OrdrConstants.ADDR_SECTION)));
                mandatoryFields.remove(OrdrConstants.ADDR_SECTION);
            } 
            //Township is mandatory for LegalLandDescription address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_TOWNSHIP) && inputMap.get(OrdrConstants.ADDR_TOWNSHIP) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_TOWNSHIP, (String)inputMap.get(OrdrConstants.ADDR_TOWNSHIP)));
                mandatoryFields.remove(OrdrConstants.ADDR_TOWNSHIP);
            } 
            //Range is mandatory for LegalLandDescription address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_RANGE) && inputMap.get(OrdrConstants.ADDR_RANGE) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_RANGE, (String)inputMap.get(OrdrConstants.ADDR_RANGE)));
                mandatoryFields.remove(OrdrConstants.ADDR_RANGE);
            } 
            //Meridian is mandatory for LegalLandDescription address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_MERIDIAN) && inputMap.get(OrdrConstants.ADDR_MERIDIAN) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_MERIDIAN, (String)inputMap.get(OrdrConstants.ADDR_MERIDIAN)));
                mandatoryFields.remove(OrdrConstants.ADDR_MERIDIAN);
            } 
        }
        
        //addressType = TownshipRangeRoadHigway
        if (addressType == OrdrConstants.ADDRESS_TYPE_TOWN_RANGE_ROAD_HWY) {
            mandatoryFields.put(OrdrConstants.ADDR_STREET_NAME, OrdrConstants.ADDR_STREET_NAME);
            mandatoryFields.put(OrdrConstants.ADDR_UNIT_NUMBER, OrdrConstants.ADDR_UNIT_NUMBER);
            
            //Street Type Code is optional for TownshipRangeRoadHigway address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_STREET_TYPE) && inputMap.get(OrdrConstants.ADDR_STREET_TYPE) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_STREET_TYPE, (String)inputMap.get(OrdrConstants.ADDR_STREET_TYPE)));
            } 
            //Street Name is mandatory for TownshipRangeRoadHigway address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_STREET_NAME) && inputMap.get(OrdrConstants.ADDR_STREET_NAME) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_STREET_NAME, (String)inputMap.get(OrdrConstants.ADDR_STREET_NAME)));
                mandatoryFields.remove(OrdrConstants.ADDR_STREET_NAME);
            } 
            //Unit Number is mandatory for TownshipRangeRoadHigway address type  
            if (inputMap.containsKey(OrdrConstants.ADDR_UNIT_NUMBER) && inputMap.get(OrdrConstants.ADDR_UNIT_NUMBER) != null) {
                characteristicValues.add(constructCharacteristicValue(OrdrConstants.ADDR_UNIT_NUMBER, (String)inputMap.get(OrdrConstants.ADDR_UNIT_NUMBER)));
                mandatoryFields.remove(OrdrConstants.ADDR_UNIT_NUMBER);
            } 
        }
        
        if (mandatoryFields.size() > 0) {
            String requiredFields = JSON.serialize(mandatoryFields.values());
           // System.debug('requiredFields:' + requiredFields);
            //Changes for Address Package 1 (BSBDT - 549)
            String location = '';
            if(inputMap.containsKey(OrdrConstants.ADDR_PROVINCE_CODE) && inputMap.get(OrdrConstants.ADDR_PROVINCE_CODE) != null){
                location = (String)inputMap.get(OrdrConstants.ADDR_PROVINCE_CODE);
            }            
            String msg = MetadataSelector.getErrorMessage(location,'DFLT0004', 'TECHNICALAVAIL');
            msg = msg.replace('EXCEPTION', 'Missing parameter -' +requiredFields);
            if(!Test.isRunningTest()){
                throw new OrdrExceptions.InvalidParameterException(msg);
            }
        }
        
        address.CharacteristicValue = characteristicValues;
        return address;
        
    }
    
    public static Map<String, String> constructServiceAddress(Id serviceAddressId) {
        //system.debug('constructServiceAddress from:'+serviceAddressId);
        Map<String, String> addressInfo = new Map<String, String>();
        
        // BP1-336 added Rate_Band__c and Forbone__c
        List<SMBCare_Address__c> serviceAddresses = [select Address_Type__c, 
                                                     Suite_Number__c, Street_Number__c, Street_Name__c, Street_Type_Code__c, Street_Direction_Code__c, City__c,
                                                     Lot__c, Block__c, Plan__c,Rate_Band__c,Forbone__c,
                                                     Quarter__c, Section__c, Township__c, Range__c, Meridian__c,
                                                     Postal_Code__c, Province__c, Municipality_Name__c, StreetType__c, 
                                                     FMS_Address_ID__c, Location_Id__c, Is_ILEC__c, COID__c,
                                                     isFIFA__c, isDropReady__c,Country__c
                                                     from SMBCare_Address__c 
                                                     where id = :serviceAddressId LIMIT 1];
        if (serviceAddresses.size() > 0) {
            if(String.isNotBlank(serviceAddressId)){addressInfo.put(OrdrConstants.ID, serviceAddressId);}
            if (String.isNotBlank(serviceAddresses[0].FMS_Address_ID__c)) {addressInfo.put(OrdrConstants.FMS_ID, serviceAddresses[0].FMS_Address_ID__c.leftPad(9, '0'));}
            if (String.isNotBlank(serviceAddresses[0].Location_Id__c)) {addressInfo.put(OrdrConstants.LOCATION_ID, serviceAddresses[0].Location_Id__c);}
            if (String.isNotBlank(serviceAddresses[0].Province__c)) {addressInfo.put(OrdrConstants.ADDR_PROVINCE_CODE, serviceAddresses[0].Province__c);}
            if (String.isNotBlank(serviceAddresses[0].COID__c)) {addressInfo.put(OrdrConstants.COID, serviceAddresses[0].COID__c);}
            if (String.isNotBlank(serviceAddresses[0].Country__c)) {addressInfo.put(OrdrConstants.ADDR_COUNTRY_CODE, serviceAddresses[0].Country__c);}
            addressInfo.put(OrdrConstants.IS_ILEC, serviceAddresses[0].Is_ILEC__c ? 'Yes' : 'No');
            // BP1-336 added Rate_Band__c and Forbone__c
            if (String.isNotBlank(serviceAddresses[0].Rate_Band__c)){
                addressInfo.put(OrdrConstants.ADDR_RATE_BAND, serviceAddresses[0].Rate_Band__c);
            }
            addressInfo.put(OrdrConstants.ADDR_FORBORNE, serviceAddresses[0].Forbone__c ? 'Yes' : 'No');
            addressInfo.put(OrdrConstants.ADDR_ISFIFA, serviceAddresses[0].isFIFA__c ? 'Yes' : 'No');
            addressInfo.put(OrdrConstants.ADDR_ISDROPREADY, serviceAddresses[0].isDropReady__c ? 'Yes' : 'No');
            
            if (serviceAddresses[0].Address_Type__c == OrdrConstants.ADDRESS_TYPE_STANDARD) {
                addressInfo.put(OrdrConstants.ADDRESS_TYPE, OrdrConstants.ADDRESS_TYPE_STANDARD);
                if (String.isNotBlank(serviceAddresses[0].Municipality_Name__c)) {addressInfo.put(OrdrConstants.ADDR_MUNICIPALITY, serviceAddresses[0].Municipality_Name__c);}
                if (String.isNotBlank(serviceAddresses[0].Postal_Code__c)) {addressInfo.put(OrdrConstants.ADDR_POSTAL_CODE, serviceAddresses[0].Postal_Code__c);}
                if (String.isNotBlank(serviceAddresses[0].Street_Direction_Code__c)) {addressInfo.put(OrdrConstants.ADDR_STREET_DIRECTION, serviceAddresses[0].Street_Direction_Code__c);}
                if (String.isNotBlank(serviceAddresses[0].StreetType__c)) {addressInfo.put(OrdrConstants.ADDR_STREET_TYPE, serviceAddresses[0].StreetType__c);}
                //system.debug('serviceAddresses[0].Street_Name__c = ' + serviceAddresses[0].Street_Name__c);
                if (String.isNotBlank(serviceAddresses[0].Street_Name__c)) {addressInfo.put(OrdrConstants.ADDR_STREET_NAME, serviceAddresses[0].Street_Name__c);}
                if (String.isNotBlank(serviceAddresses[0].Street_Number__c)) {addressInfo.put(OrdrConstants.ADDR_STREET_NUMBER, serviceAddresses[0].Street_Number__c);}
                if (String.isNotBlank(serviceAddresses[0].Suite_Number__c)) {addressInfo.put(OrdrConstants.ADDR_UNIT_NUMBER, serviceAddresses[0].Suite_Number__c);}
            }
            
            if (serviceAddresses[0].Address_Type__c == OrdrConstants.ADDRESS_TYPE_LOT_BLOCK_PLAN) {
                addressInfo.put(OrdrConstants.ADDRESS_TYPE, OrdrConstants.ADDRESS_TYPE_LOT_BLOCK_PLAN);
                if (String.isNotBlank(serviceAddresses[0].Lot__c)) {addressInfo.put(OrdrConstants.ADDR_LOT, serviceAddresses[0].Lot__c);}
                if (String.isNotBlank(serviceAddresses[0].Block__c)) {addressInfo.put(OrdrConstants.ADDR_BLOCK, serviceAddresses[0].Block__c);}
                if (String.isNotBlank(serviceAddresses[0].Plan__c)) {addressInfo.put(OrdrConstants.ADDR_PLAN, serviceAddresses[0].Plan__c);}
            }
            
            if (serviceAddresses[0].Address_Type__c == OrdrConstants.ADDRESS_TYPE_LEGAL_LAND_DESC) {
                addressInfo.put(OrdrConstants.ADDRESS_TYPE, OrdrConstants.ADDRESS_TYPE_LEGAL_LAND_DESC);
                if (String.isNotBlank(serviceAddresses[0].Quarter__c)) {addressInfo.put(OrdrConstants.ADDR_QUARTER, serviceAddresses[0].Quarter__c);}
                if (String.isNotBlank(serviceAddresses[0].Section__c)) {addressInfo.put(OrdrConstants.ADDR_SECTION, serviceAddresses[0].Section__c);}
                if (String.isNotBlank(serviceAddresses[0].Township__c)) {addressInfo.put(OrdrConstants.ADDR_TOWNSHIP, serviceAddresses[0].Township__c);}
                if (String.isNotBlank(serviceAddresses[0].Range__c)) {addressInfo.put(OrdrConstants.ADDR_RANGE, serviceAddresses[0].Range__c);}
                if (String.isNotBlank(serviceAddresses[0].Meridian__c)) {addressInfo.put(OrdrConstants.ADDR_MERIDIAN, serviceAddresses[0].Meridian__c);}
            }
            
            if (serviceAddresses[0].Address_Type__c == OrdrConstants.ADDRESS_TYPE_TOWN_RANGE_ROAD_HWY) {
                addressInfo.put(OrdrConstants.ADDRESS_TYPE, OrdrConstants.ADDRESS_TYPE_TOWN_RANGE_ROAD_HWY);
                if (String.isNotBlank(serviceAddresses[0].StreetType__c)) {addressInfo.put(OrdrConstants.ADDR_STREET_TYPE, serviceAddresses[0].StreetType__c);}
                if (String.isNotBlank(serviceAddresses[0].Street_Name__c)) {addressInfo.put(OrdrConstants.ADDR_STREET_NAME, serviceAddresses[0].Street_Name__c);}
                if (String.isNotBlank(serviceAddresses[0].Suite_Number__c)) {addressInfo.put(OrdrConstants.ADDR_UNIT_NUMBER, serviceAddresses[0].Suite_Number__c);}
            }
        }
        //system.debug('addressInfo:'+addressInfo);
        return addressInfo;
    }
    
    public static List<String> getUsedTns(String orderId) {
        List<String> tnList=new List<String>();
        /**Removed vlocity_cmt__JSONAttribute__c from the query**/
        List<OrderItem> orderItemList=[SELECT id,OrderId,Order.ParentId__c FROM OrderItem Where OrderId =:orderId order by vlocity_cmt__LineNumber__c];
        if((orderItemList==null) || (orderItemList.size()==0)){
            return tnList;
        }
        
        for(OrderItem oiObj:orderItemList){
            String ordid=oiObj.OrderId;
            if(String.isBlank(ordid)){
                continue;
            }
            //Map<String,Object> attrObj = (Map<String,Object>)JSON.deserializeUntyped(jsonText);
            //Changes start for ICCAP-40 :calling new method to get attributes from the cache
            Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> attributesMap = new Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> ();
            sObject sobj = oiObj;
            attributesMap =  (OCOM_VlocityJSONParseUtil.getItemAttributes(sobj)).get(oiObj.id);
            
            //Changes start for ICCAP-40 :calling new method to get attributes from the cache
            if(attributesMap!=null){
                for(String keyLevel1 : attributesMap.keySet()){
                    
                    String charactersticsName = keyLevel1;
                    if(String.isnotBlank(charactersticsName) && (charactersticsName.equals(OrdrConstants.TOLLFREE_TELEPHONE_NUMBER) || charactersticsName.equals(OrdrConstants.TELEPHONE_NUMBER) || charactersticsName.startsWith(OrdrConstants.TELEPHONE_NUMBER))){
                        
                        String dataType=attributesMap.get(keyLevel1).dataType;
                        if(dataType!=null){
                            if(dataType.equals('Text') || dataType.equals('Number')){
                                
                                String  charactersticsValue= attributesMap.get(keyLevel1).value;
                                
                                if(String.isNotBlank(charactersticsValue) || Test.isRunningTest()){
                                    charactersticsValue=charactersticsValue.replaceAll(' ', '');
                                    charactersticsValue=charactersticsValue.replaceAll('-', '');
                                    tnList.add(charactersticsValue);
                                }                                           
                            }
                            
                        }
                        
                    }
                    
                }
            }
        }
        return tnList;
    }  
    
    
    public static Boolean isOrderAmendReadyV2(String orderId,String childOrderId) {
        //return true;
       // System.debug('@@isOrderAmendReady is called for orderid '+orderId);
       // System.debug('@@isOrderAmendReady is called for CChildorderid '+childOrderId);
        if(String.isBlank(orderId)){
            return false;
        }
        List<OrderItem> oiList=null;
        if(String.isNotBlank(childOrderId)){
            oiList=[SELECT Id,upgradedowngrade__c,vlocity_cmt__rootitemid__c,PricebookEntry.Product2.RelationshipType__c,amendstatus__c,orderMgmtId__c,
                    pricebookentry.product2.ProductSpecification__r.name,OrderId,Order.orderMgmtId_Status__c, 
                    Order.orderMgmtId_SubStatus__c,orderMgmtId_Status__c,orderMgmtId_SubStatus__c,order.parentid__r.Master_Order_Status__c,
                    order.status,order.statuscode FROM OrderItem where order.parentid__c=:orderId and orderid=:childOrderId];
            if(oiList!=null && oiList.size()>0){
                OrderItem childOIObj=oiList.get(0);
               // system.debug('childOIObj.order.parentid__r.Master_order_status__c'+childOIObj.order.parentid__r.Master_order_status__c);
               // system.debug('childOIObj'+childOIObj.order.statuscode);
                
                if(String.isNotBlank(childOIObj.order.parentid__r.Master_order_status__c) 
                   && OrdrConstants.ORDR_COMPLETED_STATUS.equalsIgnoreCase(childOIObj.order.parentid__r.Master_order_status__c)){
                       return false;
                   }
                if(String.isNotBlank(childOIObj.order.statuscode) && 'D'.equalsIgnoreCase(childOIObj.order.statuscode)){
                    return false; 
                }
            }
            
        } else {
            oiList=[SELECT Id,upgradedowngrade__c,vlocity_cmt__rootitemid__c,PricebookEntry.Product2.RelationshipType__c,amendstatus__c,orderMgmtId__c,
                    pricebookentry.product2.ProductSpecification__r.name,OrderId,Order.orderMgmtId_Status__c, 
                    Order.orderMgmtId_SubStatus__c,orderMgmtId_Status__c,orderMgmtId_SubStatus__c,order.parentid__r.Master_Order_Status__c,
                    order.status FROM OrderItem where order.parentid__c=:orderId];
            
        }
        
        Set<Id> childOrderSet=new Set<Id>();
        Set<Id> excludedRootIdsSet=new Set<Id>();
        for(OrderItem oi:oiList){
            if(String.isNotBlank(oi.order.parentid__r.Master_order_status__c) 
               && OrdrConstants.ORDR_COMPLETED_STATUS.equalsIgnoreCase(oi.order.parentid__r.Master_order_status__c)){
                   return false;
               }
            if(oi.UpgradeDowngrade__c){
                if(String.isNotBlank(oi.vlocity_cmt__RootItemId__c)){
                    excludedRootIdsSet.add(oi.vlocity_cmt__RootItemId__c);
                }                
            }
            if(!childOrderSet.contains(oi.OrderId)){
                childOrderSet.add(oi.OrderId);
            }            
        }
        Set<Id> childOrderSetCp=new Set<Id>();
        childOrderSetCp.addAll(childOrderSet);
        //system.debug('childOrderSetCp'+childOrderSetCp);
        for(OrderItem oi:oiList){
            if(String.isNotBlank(oi.vlocity_cmt__RootItemId__c) && excludedRootIdsSet.contains(oi.vlocity_cmt__RootItemId__c)){
                continue;
            }   
            if(String.isBlank(oi.orderMgmtId__c) 
               || OrdrConstants.ORDR_ENTERING_STATUS.equalsIgnoreCase(oi.orderMgmtId_Status__c) 
               || OrdrConstants.ORDR_PROCESSED_STATUS.equalsIgnoreCase(oi.orderMgmtId_Status__c)){
                   if(//(String.isNotBlank(oi.amendstatus__c) && OrdrConstants.AMEND_STATUS_ADD.equalsIgnoreCase(oi.amendstatus__c)) || 
                       (String.isNotBlank(oi.PricebookEntry.Product2.RelationshipType__c) && 
                        OrdrConstants.PROMOTION.equalsIgnoreCase(oi.PricebookEntry.Product2.RelationshipType__c))){
                            continue;
                        }
                   childOrderSet.remove(oi.OrderId);
               }
        }
       //system.debug('childOrderSet'+childOrderSet);
        if(childOrderSet.size()==0){
            return false;
        }
        if(oiList!=null && oiList.size()>0 && oiList.get(0)!=null &&  
           ((String.isNotBlank(oiList.get(0).Order.orderMgmtId_Status__c)) &&  
            (OrdrConstants.ORDR_PONR_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c) || 
             OrdrConstants.ORDR_PROCESSED_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c) || 
             OrdrConstants.ORDR_ERROR_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c) || 
             OrdrConstants.ORDR_ENTERING_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c)))){
                 childOrderSetCp.remove(oiList.get(0).OrderId);
             }
        //system.debug('childOrderSetCp'+childOrderSetCp);
        if(childOrderSetCp.size()==0){
           // system.debug('@@returning false');//testing-pooja
            return false;
        }
       // system.debug('@@returning true');//testing-pooja
        return true;
        
    }
    
    public static Boolean isOrderAmendReady(String orderId) {
       // System.debug('isOrderAmendReady is called for orderid '+orderId);
        
        List<OrderItem> oiList=[SELECT Id,PricebookEntry.Product2.RelationshipType__c,amendstatus__c,orderMgmtId__c,pricebookentry.product2.ProductSpecification__r.name,OrderId,Order.orderMgmtId_Status__c, Order.orderMgmtId_SubStatus__c,orderMgmtId_Status__c,orderMgmtId_SubStatus__c FROM OrderItem where orderid=:orderId];
        
        for(OrderItem oi:oiList){
            if(String.isBlank(oi.orderMgmtId__c)){
                if((String.isNotBlank(oi.amendstatus__c) && OrdrConstants.AMEND_STATUS_ADD.equalsIgnoreCase(oi.amendstatus__c)) || (String.isNotBlank(oi.PricebookEntry.Product2.RelationshipType__c) && OrdrConstants.PROMOTION.equalsIgnoreCase(oi.PricebookEntry.Product2.RelationshipType__c))){
                    continue;
                }
                return false;
            }
        }
        
        if(oiList!=null && oiList.size()>0 && oiList.get(0)!=null &&  ((String.isNotBlank(oiList.get(0).Order.orderMgmtId_Status__c)) &&  (OrdrConstants.ORDR_PONR_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c) || OrdrConstants.ORDR_PROCESSED_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c) || OrdrConstants.ORDR_ERROR_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c) || OrdrConstants.ORDR_ENTERING_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c)))){
            return false;
        }
        
        return true;
        
    }
    public static Boolean isOrderObjAmendReady(Order ordObj) {
        List<OrderItem> oiList=[SELECT Id,PricebookEntry.Product2.RelationshipType__c,amendstatus__c,orderMgmtId__c,pricebookentry.product2.Product_Type__c,OrderId,Order.orderMgmtId_Status__c, Order.orderMgmtId_SubStatus__c,orderMgmtId_Status__c,orderMgmtId_SubStatus__c FROM OrderItem where orderid=:ordObj.id];
        
        for(OrderItem oi:oiList){
            if(String.isBlank(oi.orderMgmtId__c)){
                if((String.isNotBlank(oi.amendstatus__c) && OrdrConstants.AMEND_STATUS_ADD.equalsIgnoreCase(oi.amendstatus__c)) || (String.isNotBlank(oi.PricebookEntry.Product2.RelationshipType__c) && OrdrConstants.PROMOTION.equalsIgnoreCase(oi.PricebookEntry.Product2.RelationshipType__c))){
                    continue;
                }
                return false;
            }
        }
        
        if((String.isNotBlank(oiList.get(0).Order.orderMgmtId_Status__c)) &&  (OrdrConstants.ORDR_PONR_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c) || OrdrConstants.ORDR_PROCESSED_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c))){
            return false;
        }
        
        return true;
        
    }
    public static Boolean isAmendedOrderSubmitReady(Order ordObj) {
        
        List<OrderItem> oiList=[SELECT Order.Status,Id,PricebookEntry.Product2.RelationshipType__c,amendStatus__c,orderMgmtId__c,pricebookentry.product2.ProductSpecification__r.name,OrderId,Order.orderMgmtId_Status__c, Order.orderMgmtId_SubStatus__c,orderMgmtId_Status__c,orderMgmtId_SubStatus__c FROM OrderItem where orderid=:ordObj.id];
        
        for(OrderItem oi:oiList){
            if((String.isNotBlank(oi.amendstatus__c) && OrdrConstants.AMEND_STATUS_ADD.equalsIgnoreCase(oi.amendstatus__c)) || (String.isNotBlank(oi.PricebookEntry.Product2.RelationshipType__c) && OrdrConstants.PROMOTION.equalsIgnoreCase(oi.PricebookEntry.Product2.RelationshipType__c))){
                continue;
            }
            if(String.isBlank(oi.orderMgmtId__c)){
                return false;
            }
        }
        
        if((oiList!=null && oiList.size()>0) &&((oiList.get(0).Order.Status!='Not Submitted')||((String.isNotBlank(oiList.get(0).Order.orderMgmtId_Status__c)) &&  (OrdrConstants.ORDR_PONR_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c) || OrdrConstants.ORDR_PROCESSED_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c))))){
            return false;
        }
        
        return true;
        
    }
    
    public static Boolean isAmendedOrderSubmittedAndFailedById(String orderId) {
        
        List<OrderItem> oiList=[SELECT Order.Status,PricebookEntry.Product2.RelationshipType__c,Id,amendStatus__c,orderMgmtId__c,pricebookentry.product2.ProductSpecification__r.name,OrderId,Order.orderMgmtId_Status__c, Order.orderMgmtId_SubStatus__c,orderMgmtId_Status__c,orderMgmtId_SubStatus__c FROM OrderItem where orderid=:orderId];
        
        for(OrderItem oi:oiList){
            if((String.isNotBlank(oi.amendstatus__c) && OrdrConstants.AMEND_STATUS_ADD.equalsIgnoreCase(oi.amendstatus__c))|| (String.isNotBlank(oi.PricebookEntry.Product2.RelationshipType__c) && OrdrConstants.PROMOTION.equalsIgnoreCase(oi.PricebookEntry.Product2.RelationshipType__c))){
                continue;
            }
            if(String.isBlank(oi.orderMgmtId__c)){
                return false;
            }
        }        
        if((oiList!=null && oiList.size()>0) &&  oiList.get(0).Order.Status=='Not Submitted' && String.isNotBlank(oiList.get(0).Order.orderMgmtId_Status__c) && (OrdrConstants.ORDR_PONR_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c) || OrdrConstants.ORDR_PROCESSED_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c) || OrdrConstants.NC_ORDR_ERROR_STATUS.equalsIgnoreCase(oiList.get(0).Order.orderMgmtId_Status__c)) ){
            return  true;
        }     
        
        return false;
        
    }
    public static Boolean isAmendedOrderSubmittedAndFailed(Order ordObj) {
        
        if(ordObj!=null){
            return  isAmendedOrderSubmittedAndFailedById(ordObj.id);  
        }
        
        return false;
        
    }
    public static void updateCharactersticsJsonBasedOnAmendReadinessOnOrder(Map<id,Order> orderArgMap){
        Map<Id,OrderItem> orderItemMap=new Map<Id,OrderItem>([select id from OrderItem where orderid in :orderArgMap.keySet()]);
        for(String orderId:orderArgMap.keySet()){
            Order ordObj=orderArgMap.get(orderId);
            if(!(String.isNotBlank(ordObj.status) &&(ordObj.status.equals('Submitted') || ordObj.status.equals('Activated')))){
                continue;
            }
        }
        updateCharactersticsJsonBasedOnAmendReadiness(orderItemMap,true);
    }
    
    public static void updateCharactersticsJsonBasedOnAmendReadiness(Map<id,OrderItem> orderItemArgMap,boolean execute){         
        //Removed vlocity_cmt__JSONAttribute__c field from the query to fix heap size 
        List<OrderItem> orderItemList=[select Work_Order__r.Scheduled_Datetime__c,Order.RequestedDate__c,Order.status,Order.orderMgmtId_Status__c, Order.orderMgmtId_SubStatus__c ,orderMgmtId__c,pricebookentry.product2.ProductSpecification__r.name,orderMgmtId_Status__c,orderMgmtId_SubStatus__c,OrderId from orderitem where id in :orderItemArgMap.keySet() ];
        
        Map<Id,OrderItem> orderItemMap = new  Map<Id,OrderItem>();
        Map<Id,Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper>> attributesMap = new Map<Id,Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper>>();
        for(OrderItem orderItemArg: orderItemList) {
            orderItemMap.put(orderItemArg.id,orderItemArg);
        }
        attributesMap = OCOM_VlocityJSONParseUtil.getDetailedAttributesFromJSON(orderItemMap);
        
        for(OrderItem orderItemArg: orderItemList) {
            if(!(String.isNotBlank(orderItemArg.Order.status) &&(orderItemArg.Order.status.equals('Submitted') || orderItemArg.Order.status.equals('Activated')))){
                return;
            }
            if(String.isBlank(orderItemArg.orderMgmtId__c)){
                continue;
            }
            if(((String.isNotBlank(orderItemArg.Order.orderMgmtId_Status__c)) &&  (OrdrConstants.ORDR_PONR_STATUS.equalsIgnoreCase(orderItemArg.Order.orderMgmtId_Status__c) || OrdrConstants.ORDR_PROCESSED_STATUS.equalsIgnoreCase(orderItemArg.Order.orderMgmtId_Status__c)))){
                updateCharactersticJson(orderItemArg, attributesMap.get(orderItemArg.Id));
                continue;
            }
            if(String.isNotBlank(orderItemArg.pricebookentry.product2.ProductSpecification__r.name) && OrdrConstants.WIRELESS_PRODUCT_TYPE_NAME.equalsIgnoreCase(orderItemArg.pricebookentry.product2.ProductSpecification__r.name)){
                if((String.isNotBlank(orderItemArg.orderMgmtId_SubStatus__c) &&  OrdrConstants.OI_COMPLETED_SUBSTATUS.equalsIgnoreCase(orderItemArg.orderMgmtId_SubStatus__c)) 
                   &&
                   (String.isNotBlank(orderItemArg.orderMgmtId_Status__c) &&  (OrdrConstants.OI_PROCESSING_STATUS.equalsIgnoreCase(orderItemArg.orderMgmtId_Status__c) || OrdrConstants.OI_PROCESSED_STATUS.equalsIgnoreCase(orderItemArg.orderMgmtId_Status__c)))
                  ){
                      updateCharactersticJson(orderItemArg, attributesMap.get(orderItemArg.Id));
                      continue;
                  }
            } else {
                if(orderItemArg.Work_Order__r.Scheduled_Datetime__c!=null){
                    DateTime dt=orderItemArg.Work_Order__r.Scheduled_Datetime__c;
                    Date bookedDate=Date.newinstance(dT.year(), dT.month(), dT.day());
                    Date todate=Date.today();
                    if(bookedDate!=null){
                        Integer difference = todate.daysBetween(bookedDate);
                        if(difference<0){
                            updateCharactersticJson(orderItemArg, attributesMap.get(orderItemArg.Id));
                            continue;
                        }
                    }
                    
                } else {                
                    Date dueDate=orderItemArg.order.RequestedDate__c;
                    Date todate=Date.today();
                    if(dueDate!=null){
                        Integer difference = todate.daysBetween(dueDate);
                        if(difference<0){
                            updateCharactersticJson(orderItemArg, attributesMap.get(orderItemArg.Id));
                            continue;
                        }
                    }
                    
                }
                
            }     
        }
        if(execute){
            update orderItemList;
        }
        
        
    }
    
    
    
    public static void updateCharactersticsJsonBasedOnAmendReadinessWithOIList(List<OrderItem> orderItemArgList,boolean execute){         
        if(String.isBlank(prodSpecId) ){
            List<Product2> prodList=[SELECT Id, ProductSpecification__c, Sellable__c, orderMgmtId__c,name FROM Product2 where name=:OrdrConstants.NHP_PROD_SPEC_NAME]; 
            if(prodList!=null && prodList.size()>0){
                prodSpecId=prodList.get(0).id;
            } 
            //System.debug('prodSpecId='+prodSpecId);
        }
        
        List<OrderItem> orderItemList=[select Work_Order__r.Scheduled_Datetime__c,Order.RequestedDate__c,Order.status,Order.orderMgmtId_Status__c, Order.orderMgmtId_SubStatus__c ,orderMgmtId__c,pricebookentry.product2.ProductSpecification__r.name,orderMgmtId_Status__c,orderMgmtId_SubStatus__c,OrderId,pricebookentry.product2.ProductSpecification__c,vlocity_cmt__Product2Id__c,order.ParentId__c,vlocity_cmt__AttributeSelectedValues__c from orderitem where id in :orderItemArgList ];
        for(OrderItem orderItemObj: orderItemList) {
            //System.debug('orderItemObj.pricebookentry.product2.ProductSpecification__c='+orderItemObj.pricebookentry.product2.ProductSpecification__c);
            if(String.isNotBlank(prodSpecId)&& prodSpecId.equals(orderItemObj.pricebookentry.product2.ProductSpecification__c)){
                //System.debug('return nhp');
                return;
            }
        }

        Map<Id,OrderItem> orderItemMap = new  Map<Id,OrderItem>();
        Map<Id,Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper>> attributesMap = new Map<Id,Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper>>();
        for(OrderItem orderItemArg: orderItemList) {
            orderItemMap.put(orderItemArg.id,orderItemArg);
        }
        attributesMap = OCOM_VlocityJSONParseUtil.getDetailedAttributesFromJSON(orderItemMap);
        
        for(OrderItem orderItemArg: orderItemList) {
            if(!(String.isNotBlank(orderItemArg.Order.status) &&(orderItemArg.Order.status.equals('Submitted') || orderItemArg.Order.status.equals('Activated')))){
                
                return;
            }
            if(String.isBlank(orderItemArg.orderMgmtId__c)){            
                continue;
            }
            if(((String.isNotBlank(orderItemArg.Order.orderMgmtId_Status__c)) &&  (OrdrConstants.ORDR_PONR_STATUS.equalsIgnoreCase(orderItemArg.Order.orderMgmtId_Status__c) || OrdrConstants.ORDR_PROCESSED_STATUS.equalsIgnoreCase(orderItemArg.Order.orderMgmtId_Status__c)))){
                updateCharactersticJson(orderItemArg, attributesMap.get(orderItemArg.Id));             
                continue;
            }
            if(String.isNotBlank(orderItemArg.pricebookentry.product2.ProductSpecification__r.name) && OrdrConstants.WIRELESS_PRODUCT_TYPE_NAME.equalsIgnoreCase(orderItemArg.pricebookentry.product2.ProductSpecification__r.name)){
                if((String.isNotBlank(orderItemArg.orderMgmtId_SubStatus__c) &&  OrdrConstants.OI_COMPLETED_SUBSTATUS.equalsIgnoreCase(orderItemArg.orderMgmtId_SubStatus__c)) 
                   &&
                   (String.isNotBlank(orderItemArg.orderMgmtId_Status__c) &&  (OrdrConstants.OI_PROCESSING_STATUS.equalsIgnoreCase(orderItemArg.orderMgmtId_Status__c) || OrdrConstants.OI_PROCESSED_STATUS.equalsIgnoreCase(orderItemArg.orderMgmtId_Status__c)))
                  ){
                      updateCharactersticJson(orderItemArg, attributesMap.get(orderItemArg.Id));                  
                      continue;
                  }
            } else {
                if(orderItemArg.Work_Order__r.Scheduled_Datetime__c!=null){
                    DateTime dt=orderItemArg.Work_Order__r.Scheduled_Datetime__c;
                    Date bookedDate=Date.newinstance(dT.year(), dT.month(), dT.day());
                    Date todate=Date.today();
                    if(bookedDate!=null){
                        Integer difference = todate.daysBetween(bookedDate);
                        if(difference<0){
                            updateCharactersticJson(orderItemArg, attributesMap.get(orderItemArg.Id));
                            continue;
                        }
                    }
                    
                } else {                
                    Date dueDate=orderItemArg.order.RequestedDate__c;
                    Date todate=Date.today();
                    if(dueDate!=null){
                        Integer difference = todate.daysBetween(dueDate);
                        if(difference<0){
                            if(orderItemArg!= null){
                                updateCharactersticJson(orderItemArg, attributesMap.get(orderItemArg.Id));
                            }
                            continue;
                        }
                    }
                    
                }
            }     
        }
        if(execute){          
            update orderItemList;            
        }
        
        
    }
    
    
    @TestVisible  private static void updateCharactersticJson(OrderItem orderItemObj, Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> attributesMap){    
        
        if(null !=orderItemObj  && String.isNotBlank(orderItemObj.OrderId)) {
            if(attributesMap !=null){
                for (String key : attributesMap.keySet()) {
                    string attributeName='';
                     attributeName = key ;
                    OCOM_VlocityJSONParseUtil.JSONWrapper wrap = new OCOM_VlocityJSONParseUtil.JSONWrapper();
                    wrap.isReadOnly=true;
                    // if( null != attributeName && null !=attributesMap && null !=attributesMap.get('isreadonly__c') ){
                    if( null != attributeName && null !=attributesMap && attributesMap.containskey('isreadonly__c') ){       
                        Boolean readOnlyValue = (Boolean)attributesMap.get('isreadonly__c').isReadOnly; 
                        if(!readOnlyValue){
                            attributesMap.put('isreadonly__c',wrap);  
                        }                       
                    }
                }    
            }
            //orderItemObj.vlocity_cmt__JSONAttribute__c= JSON.serialize(attributesMap);
            //Tejaswini - Changes as per v2 json upgrade
            orderItemObj.vlocity_cmt__AttributeSelectedValues__c = JSON.serialize(attributesMap);
        }
    }    // Added by Arvind as part of BF-844
    
    @future(callout=true)
    public static void submitAmendedOrder(String orderId){
        List<Order> ordrObjList=[select vlocity_cmt__ValidationMessage__c,vlocity_cmt__ValidationStatus__c,orderMgmtId__c from Order where id=:orderId] ;
        Order orderRecord=null;
        if(ordrObjList!=null && ordrObjList.size()>0){
            orderRecord=ordrObjList.get(0);
        }
        if(orderRecord==null){             
            return ;
        }
        if(!isOrderAmendReady(orderId)){
            // Thomas QC-8906
            // set flag to indicate that CAR status update amend order notification to NetCracker still required
            orderRecord.CAR_Approval_Notification_Required__c = true;
           // System.debug('OrdrUtilities::submitAmendedOrder() CAR_Approval_Notification_Required__c('+orderRecord.CAR_Approval_Notification_Required__c+')');
            update orderRecord;
            return;
        }
        
        OrdrSubmitCustomerOrder.isOrderAmendCreditRelated=true;
        Object responseObject=OrdrSubmitCustomerOrder.submitOrder(orderId);
        String externalOrdNo='';
       // system.debug('OrdrUtilities::submitAmendedOrder() responseObject(' + responseObject + ')');
        if (responseObject!=null) {
            TpFulfillmentCustomerOrderV3.CustomerOrder customerOrderResponse =(TpFulfillmentCustomerOrderV3.CustomerOrder) responseObject;
            TpCommonBaseV3.CharacteristicValue[] charactersticsValList=customerOrderResponse.CharacteristicValue;                    
            for (TpCommonBaseV3.CharacteristicValue charactersticsVal : charactersticsValList) {
                if (null!=charactersticsVal) {
                    //TpCommonBaseV3.Characteristic charRes= charactersticsVal.Characteristic;                                       
                   // System.debug(charactersticsVal.Value[0]);
                    externalOrdNo=charactersticsVal.Value[0];
                }                    
            }
        }
        
        
        if ((responseObject==null) || (String.isBlank(externalOrdNo))) {            
            orderRecord.vlocity_cmt__ValidationMessage__c = 'Order submission failed after Credit approval. ';
            orderRecord.vlocity_cmt__ValidationStatus__c = 'SubmitFailed';
            orderRecord.vlocity_cmt__ValidationDate__c = system.now();
            orderRecord.orderMgmtId__c=externalOrdNo;
            // Thomas QC-8906
            orderRecord.CAR_Approval_Notification_Required__c = true;
            update orderRecord;
           // System.debug('OrdrUtilities::submitAmendedOrder() submit failed for orderid=(' + orderId + ')');
            return ;
        } else {
            // Thomas - QC6738
            orderRecord.status = 'Submitted';
            orderRecord.vlocity_cmt__ValidationMessage__c = 'Submitted after credit approval';
            orderRecord.vlocity_cmt__ValidationStatus__c = 'Success';
            orderRecord.vlocity_cmt__ValidationDate__c = system.now();
            orderRecord.orderMgmtId__c=externalOrdNo;
            // Thomas QC-8906
            orderRecord.CAR_Approval_Notification_Required__c = false;
            update orderRecord; 
           // System.debug('OrdrUtilities::submitAmendedOrder() submit is successful  for orderid=(' + orderId + ')');
            //createAssets(orderRecord.id);
        }       
    }
    @future(callout=false)
    public static void createAssets(String objId){
        vlocity_cmt.DefaultObjectCopierImplementation objCopier =  new vlocity_cmt.DefaultObjectCopierImplementation();
        vlocity_cmt.FlowStaticMap.flowMap.put('objectCopier',objCopier.copyObject(objId, '')); 
        return;
    } 
    public static Boolean isCharactersticChangedForAmend(String currentJson,String previousJson,String productJson){
        OrdrUtilities.ignoreCharNameForAmend=false;
        return isCharactersticChanged(currentJson,previousJson,productJson);
    }
    public static Boolean isCharactersticChanged(String currentJson,String previousJson,String productJson){
        if(String.isBlank(currentJson) || String.isBlank(previousJson) || String.isBlank(productJson)){
            return false;
        }
        
        Set<String> currentCharSet=getCharactersticsNameSet(currentJson);
        Set<String> oldCharSet=getCharactersticsNameSet(previousJson);
       // System.debug('**M*currentCharSet*'+currentCharSet);
        //System.debug('**M*oldCharSet*'+oldCharSet);
        Set<String> currentCharTempSet=new Set<String>();
        currentCharTempSet.addAll(currentCharSet);
        currentCharTempSet.removeAll(oldCharSet);
        //System.debug('**M*currentCharTempSet*'+currentCharTempSet);
        Set<String> addedCharSet=new Set<String>();
        addedCharSet.addAll(currentCharTempSet);
        //System.debug('**M*addedCharSet*'+addedCharSet);
        if(addedCharSet.size()>0){
            return true;
        }
        
        Set<String> previousCharTempSet=new Set<String>();
        previousCharTempSet.addAll(oldCharSet);
        previousCharTempSet.removeAll(currentCharSet);
        Set<String> deletedCharSet=new Set<String>();
        deletedCharSet.addAll(previousCharTempSet);
        //System.debug('**M*deletedCharSet*'+deletedCharSet);
        if(deletedCharSet.size()>0){
            return true;
        }
        
        currentCharTempSet=new Set<String>();
        currentCharTempSet.addAll(currentCharSet);
        currentCharTempSet.retainAll(oldCharSet);
        Set<String> changedCharSet=new Set<String>();
        changedCharSet.addAll(currentCharTempSet);
        //System.debug('**M*changedCharSet*'+changedCharSet);
        Map<String,String> currentCharNameValMap= getCharactersticsValueMap(currentJson);
        Map<String,String> previousCharNameValMap= getCharactersticsValueMap(previousJson);
        
        List<String> offerCharNameList=getCharactersticsNameList(productJson);
        
        for(String charName:offerCharNameList){                     
           // System.debug('**M*charName*'+charName);
            if(addedCharSet!=null && addedCharSet.contains(charName)){
                continue;
            }
            if(deletedCharSet!=null && deletedCharSet.contains(charName)){
                continue;
            }
            if(changedCharSet!=null && changedCharSet.contains(charName)){
                String oldVal=previousCharNameValMap.get(charName);
                String newVal=currentCharNameValMap.get(charName);
                
               // System.debug('**M*charName*'+charName +'**M*oldVal*'+oldVal+'**M*newVal*'+newVal);
                if((String.isNotBlank(oldVal) && String.isBlank(newVal) ) || (String.isBlank(oldVal) && String.isNotBlank(newVal) ) || (String.isNotBlank(oldVal) && String.isNotBlank(newVal) && !oldVal.equalsIgnoreCase(newVal))){
                    //System.debug('**M* Charactersitics Changed*'+charName +'**M*oldVal*'+oldVal+'**M*newVal*'+newVal);
                    
                    return true;
                }
                         
            }         
        }
        
        return false;
    }
    public static Boolean isCharactersticChangedForOI(OrderItem oiObj){
        OrdrUtilities.ignoreCharNameForAmend=true;
        Map<String, Object> fieldsToValue = oiObj.getPopulatedFieldsAsMap();
        //if((fieldsToValue.get('Previous_JSONAttribute__c')==null) || (fieldsToValue.get('vlocity_cmt__JSONAttribute__c')==null) || (fieldsToValue.get('pricebookentry.product2.vlocity_cmt__JSONAttribute__c')==null)){
        //Tejaswini - Changes as per v2 json upgrade
        if((fieldsToValue.get('Previous_JSONAttribute__c')==null) || (fieldsToValue.get('vlocity_cmt__AttributeSelectedValues__c')==null) || (fieldsToValue.get('pricebookentry.product2.vlocity_cmt__AttributeDefaultValues__c')==null)){
            //List<OrderItem> oiList=[Select vlocity_cmt__JSONAttribute__c,Previous_JSONAttribute__c,pricebookentry.product2.vlocity_cmt__JSONAttribute__c from OrderItem where id=:oiObj.id order by vlocity_cmt__LineItemNumber__c asc];
            //Tejaswini - Changes as per v2 json upgrade
            List<OrderItem> oiList=[Select vlocity_cmt__AttributeSelectedValues__c,Previous_JSONAttribute__c,pricebookentry.product2.vlocity_cmt__AttributeDefaultValues__c from OrderItem where id=:oiObj.id order by vlocity_cmt__LineItemNumber__c asc];
            if(oiList==null){
                return null;
            }
            if(oiList.size()>0){
                oiObj=oiList.get(0);
                //Tejaswini - Changes as per v2 json upgrade
                if(String.isBlank(oiObj.vlocity_cmt__AttributeSelectedValues__c) || String.isBlank(oiObj.Previous_JSONAttribute__c)){
                    return false;
                }
            }
        }
        //Tejaswini - Changes as per v2 json upgrade
        return isCharactersticChanged(oiObj.vlocity_cmt__AttributeSelectedValues__c,oiObj.Previous_JSONAttribute__c,oiObj.pricebookentry.product2.vlocity_cmt__AttributeDefaultValues__c);
    }
    
    @TestVisible   private static Set<String> getCharactersticsNameSet(String charJson){
        //Set<String> charNameSet=new Set<String>();
        Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> jsonWrapperMap=OCOM_VlocityJSONParseUtil.getAttributesFromJSON(charJson);
        if(jsonWrapperMap!=null){
            Set<String> jsonWrapSet=jsonWrapperMap.keySet();
            if(jsonWrapSet!=null && ignoreCharNameForAmend){
                jsonWrapSet.removeAll(OrdrConstants.ignoreCharNameSetForBeforeAndAfterView);
            }
            return jsonWrapSet;
        }
        return null;
    }
    
    @TestVisible  private static Map<String,String> getCharactersticsValueMap(String charJson){
        Map<String,String> charNameValueMap=new Map<String,String>();
        Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> jsonWrapperMap=OCOM_VlocityJSONParseUtil.getAttributesFromJSON(charJson);
        if(jsonWrapperMap!=null){
            for(String jsonKey:jsonWrapperMap.keySet()){
                if(ignoreCharNameForAmend && OrdrConstants.ignoreCharNameSetForBeforeAndAfterView.contains(jsonKey)){
                    continue;
                }
                OCOM_VlocityJSONParseUtil.JSONWrapper wrapper=jsonWrapperMap.get(jsonKey);
                if(wrapper!=null){
                    String jsonVal=wrapper.value;
                    
                    charNameValueMap.put(jsonKey,jsonVal);
                }
            }
        }
        return charNameValueMap;
    }
    
    @TestVisible    private static List<String> getCharactersticsNameList(String charJson){
        List<String> charNameList=new List<String>();
        Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> jsonWrapperMap=OCOM_VlocityJSONParseUtil.getAttributesFromJSON(charJson);
        if(jsonWrapperMap!=null && jsonWrapperMap.keySet()!=null){
            Set<String> jsonWrapSet=jsonWrapperMap.keySet();
            if(jsonWrapSet!=null && ignoreCharNameForAmend){
                jsonWrapSet.removeAll(OrdrConstants.ignoreCharNameSetForBeforeAndAfterView);
            }
            charNameList.addAll(jsonWrapSet);
        }
        return charNameList; 
        
    }
    
    //@future(callout=true)
    public static void preLoadTNR(Set<String> orderIdSet){  
        if(orderIdSet!=null){
            for(String orderId:orderIdSet){
                // if(!Test.isRunningTest()){
                if(System.isFuture()){
                    preLoadTNRSync(orderId);
                } else {
                    preLoadTNRFuture(orderId);
                }
                
                //}
                
            }
        }
    }
    public static void preLoadTNRSync(String orderId){       
        List<Order> ordList=[select Service_Address__c from order where id=:orderId];
        if(ordList!=null && ordList.size()>0){
            String addressId=ordList.get(0).Service_Address__c; 
            if(String.isNotBlank(addressId)){
                SMBCare_Address__c addressObj=new SMBCare_Address__c(id=addressId); 
                try{
                    //OrdrTnServiceAddress resultSaObj= OrdrTnReservationImpl.getNpaNxxListTnList(orderId,null, addressObj, UserInfo.getUserId(), OrdrTnReservationType.WLN,null,null,false);
                    OrdrTnReservationImpl.getNpaNxxListTnList(orderId,null, addressObj, UserInfo.getUserId(), OrdrTnReservationType.WLN,null,null,false);
                }catch(Exception e){
                    System.debug(e.getMessage());
                }
            }  
        } 
    }
    @future(callout=true)
    public static void preLoadTNRFuture(String orderId){         
        List<Order> ordList=[select Service_Address__c from order where id=:orderId];
        if(ordList!=null && ordList.size()>0){
            String addressId=ordList.get(0).Service_Address__c; 
            if(String.isNotBlank(addressId)){
                SMBCare_Address__c addressObj=new SMBCare_Address__c(id=addressId); 
                try{
                    //OrdrTnServiceAddress resultSaObj= 
                    OrdrTnReservationImpl.getNpaNxxListTnList(orderId,null, addressObj, UserInfo.getUserId(), OrdrTnReservationType.WLN,null,null,false);
                }catch(Exception e){
                    System.debug(e.getMessage());
                }
            }  
        } 
        
    }
    
    
    public static List<webservice_integration_error_log__c> auditLogs(String apexClassMethod,
                                                                      String externalSystemName,
                                                                      String websericeName,
                                                                      String objectName,
                                                                      String recordId,
                                                                      Boolean isCalloutError,
                                                                      Boolean isGenericError,
                                                                      String msg,
                                                                      String stacktraceMsg,
                                                                      String requestPayload){
                                                                          try{
                                                                              // useAuditFlag=true;
                                                                              map<string,schema.recordtypeinfo> errorLogRecordTypeMap=webservice_integration_error_log__c.sobjecttype.getdescribe().getrecordtypeinfosbyname();
                                                                              webservice_integration_error_log__c errorLog=new webservice_integration_error_log__c();
                                                                              errorLog.apex_class_and_method__c=apexClassMethod;
                                                                              errorLog.external_system_name__c=externalSystemName;
                                                                              errorLog.webservice_name__c=websericeName;
                                                                              errorLog.object_name__c=objectName;
                                                                              errorLog.sfdc_record_id__c=recordId;
                                                                              errorLog.Request_Payload__c = requestPayload;
                                                                              if(isCalloutError || isGenericError){
                                                                                  if(errorLogRecordTypeMap.containskey('Failure')){
                                                                                      errorLog.recordtypeid=errorLogRecordTypeMap.get('Failure').getrecordtypeid();
                                                                                  }                
                                                                                  errorLog.stack_trace__c=stacktraceMsg;
                                                                              }  else {
                                                                                  if(errorLogRecordTypeMap.containskey('Success')){
                                                                                      errorLog.recordtypeid=errorLogRecordTypeMap.get('Success').getrecordtypeid();
                                                                                  }                
                                                                              }           
                                                                              errorLog.error_code_and_message__c=msg;
                                                                              errorLog.error_code_and_message__c=(string.isnotblank(errorLog.error_code_and_message__c)&&errorLog.error_code_and_message__c.length()>32767?errorLog.error_code_and_message__c.substring(0,32767):errorLog.error_code_and_message__c);
                                                                              errorLog.stack_trace__c=(string.isnotblank(errorLog.stack_trace__c)&&errorLog.stack_trace__c.length()>32767?errorLog.stack_trace__c.substring(0,32767):errorLog.stack_trace__c);
                                                                              insert errorLog;
                                                                              errList.add(errorLog); 
                                                                              
                                                                          }catch(exception e){
                                                                              system.debug(e.getmessage());
                                                                          }
                                                                          
                                                                          return errList;
                                                                          
                                                                      }
    
    public static webservice_integration_error_log__c auditLogRecord(String apexClassMethod,
                                                                     String externalSystemName,
                                                                     String websericeName,
                                                                     String objectName,
                                                                     String recordId,
                                                                     Boolean isCalloutError,
                                                                     Boolean isGenericError,
                                                                     String msg,
                                                                     String stacktraceMsg){
                                                                         webservice_integration_error_log__c errorLogRecord=new webservice_integration_error_log__c();
                                                                         try{
                                                                             // useAuditFlag=true;
                                                                             map<string,schema.recordtypeinfo> errorLogRecordTypeMap=webservice_integration_error_log__c.sobjecttype.getdescribe().getrecordtypeinfosbyname();
                                                                             webservice_integration_error_log__c errorLog=new webservice_integration_error_log__c();
                                                                             errorLog.apex_class_and_method__c=apexClassMethod;
                                                                             errorLog.external_system_name__c=externalSystemName;
                                                                             errorLog.webservice_name__c=websericeName;
                                                                             errorLog.object_name__c=objectName;
                                                                             errorLog.sfdc_record_id__c=recordId;
                                                                             if(isCalloutError || isGenericError){
                                                                                 if(errorLogRecordTypeMap.containskey('Failure')){
                                                                                     errorLog.recordtypeid=errorLogRecordTypeMap.get('Failure').getrecordtypeid();
                                                                                 }                
                                                                                 errorLog.stack_trace__c=stacktraceMsg;
                                                                             }  else {
                                                                                 if(errorLogRecordTypeMap.containskey('Success')){
                                                                                     errorLog.recordtypeid=errorLogRecordTypeMap.get('Success').getrecordtypeid();
                                                                                 }                
                                                                             }           
                                                                             errorLog.error_code_and_message__c=msg;
                                                                             errorLog.error_code_and_message__c=(string.isnotblank(errorLog.error_code_and_message__c)&&errorLog.error_code_and_message__c.length()>32767?errorLog.error_code_and_message__c.substring(0,32767):errorLog.error_code_and_message__c);
                                                                             errorLog.stack_trace__c=(string.isnotblank(errorLog.stack_trace__c)&&errorLog.stack_trace__c.length()>32767?errorLog.stack_trace__c.substring(0,32767):errorLog.stack_trace__c);
                                                                             
                                                                             insert errorLog;
                                                                             errorLogRecord=errorLog;
                                                                             
                                                                         }catch(exception e){
                                                                             system.debug(e.getmessage());
                                                                         }
                                                                         
                                                                         return errorLogRecord;
                                                                         
                                                                     }   
    
    
    public static List<webservice_integration_error_log__c> auditLogs(String apexClassMethod,
                                                                      String externalSystemName,
                                                                      String websericeName,
                                                                      String objectName,
                                                                      String recordId,
                                                                      Boolean isCalloutError,
                                                                      Boolean isGenericError,
                                                                      String msg,
                                                                      String stacktraceMsg){
                                                                          try{
                                                                              // useAuditFlag=true;
                                                                              map<string,schema.recordtypeinfo> errorLogRecordTypeMap=webservice_integration_error_log__c.sobjecttype.getdescribe().getrecordtypeinfosbyname();
                                                                              webservice_integration_error_log__c errorLog=new webservice_integration_error_log__c();
                                                                              errorLog.apex_class_and_method__c=apexClassMethod;
                                                                              errorLog.external_system_name__c=externalSystemName;
                                                                              errorLog.webservice_name__c=websericeName;
                                                                              errorLog.object_name__c=objectName;
                                                                              errorLog.sfdc_record_id__c=recordId;
                                                                              if(isCalloutError || isGenericError){
                                                                                  if(errorLogRecordTypeMap.containskey('Failure')){
                                                                                      errorLog.recordtypeid=errorLogRecordTypeMap.get('Failure').getrecordtypeid();
                                                                                  }                
                                                                                  errorLog.stack_trace__c=stacktraceMsg;
                                                                              }  else {
                                                                                  if(errorLogRecordTypeMap.containskey('Success')){
                                                                                      errorLog.recordtypeid=errorLogRecordTypeMap.get('Success').getrecordtypeid();
                                                                                  }                
                                                                              }           
                                                                              errorLog.error_code_and_message__c=msg;
                                                                              errorLog.error_code_and_message__c=(string.isnotblank(errorLog.error_code_and_message__c)&&errorLog.error_code_and_message__c.length()>32767?errorLog.error_code_and_message__c.substring(0,32767):errorLog.error_code_and_message__c);
                                                                              errorLog.stack_trace__c=(string.isnotblank(errorLog.stack_trace__c)&&errorLog.stack_trace__c.length()>32767?errorLog.stack_trace__c.substring(0,32767):errorLog.stack_trace__c);
                                                                              // insert errorLog;
                                                                              errList.add(errorLog); 
                                                                              
                                                                          }catch(exception e){
                                                                              system.debug(e.getmessage());
                                                                          }
                                                                          
                                                                          return errList;
                                                                          
                                                                      }   
    
    
    public static void auditLogs(String apexClassMethod,
                                 String externalSystemName,
                                 String websericeName,
                                 String objectName,
                                 String recordId,
                                 Boolean isError,
                                 String errorMsg,
                                 String stacktraceMsg) {
                                     if(useAuditFlag == false){
                                         List<webservice_integration_error_log__c> errors = auditLogs(apexClassMethod,
                                                                                                      externalSystemName,
                                                                                                      websericeName,
                                                                                                      objectName,
                                                                                                      recordId,
                                                                                                      isError,
                                                                                                      isError,
                                                                                                      errorMsg,
                                                                                                      stacktraceMsg);
                                         //system.debug('errors@@@'+errors);
                                         insert errors;
                                     }
                                     
                                     
                                 }
    public static Boolean isCancellable(String orderId){
        Boolean isOrderCancellable=true;
        List<OrderItem> orderItemRecs = [Select Id, orderMgmtId_Status__c, order.orderMgmtId_Status__c  FROM OrderItem WHERE OrderId = :orderId];
        if(orderItemRecs != null && orderItemRecs.size()>0){
            for(OrderItem orderRec : orderItemRecs){               
                if((String.isNotBlank(orderRec.orderMgmtId_Status__c) && OrdrConstants.OI_PONR_STATUS.equalsIgnoreCase(orderRec.orderMgmtId_Status__c)) || (String.isNotBlank(orderRec.orderMgmtId_Status__c) && OrdrConstants.OI_COMPLETED_STATUS.equalsIgnoreCase(orderRec.orderMgmtId_Status__c)) || (String.isNotBlank(orderRec.order.orderMgmtId_Status__c ) && OrdrConstants.NC_ORDR_PONR_STATUS.equalsIgnoreCase(orderRec.order.orderMgmtId_Status__c)) || (String.isNotBlank(orderRec.order.orderMgmtId_Status__c ) && OrdrConstants.NC_ORDR_PROCESSED_STATUS.equalsIgnoreCase(orderRec.order.orderMgmtId_Status__c))){
                    isOrderCancellable=false; 
                }
            }
        }
        return isOrderCancellable;
    }
    
    public static Map<String,Boolean> isCancellable(Set<String> orderIdSet){
       // System.debug('orderIdSet@@@'+orderIdSet);
        Map<String,Boolean> OrderIdToIsCancellableMap = new Map<String,Boolean>();
        List<Order> orderRecs = [Select Type,Id, orderMgmtId_Status__c,parentId__c ,
                                 (select orderid,Contract_Line_Item__r.vlocity_cmt__ContractId__r.status from orderitems)
                                 from Order where id = :orderIdSet  or parentId__c = :orderIdSet order by parentId__c asc];
       // system.debug('isCancellable 0 '+orderRecs);
        if(null != orderRecs && orderRecs.size() > 0){
            for(order orderRec : orderRecs){
                //system.debug('isCancellable 1 '+orderRec);
                String orderId = orderRec.id;
                Boolean contractRegistered=false;
                for(OrderItem orderItemRec : orderRec.orderitems){
                    if(orderRec.Type!=OrdrConstants.ORDER_TYPE_CHANGE &&(String.isNotBlank(orderItemRec.Contract_Line_Item__r.vlocity_cmt__ContractId__r.status) &&
                                                                         ('Customer Accepted'.equalsIgnoreCase(orderItemRec.Contract_Line_Item__r.vlocity_cmt__ContractId__r.status)
                                                                          || 'Contract Accepted'.equalsIgnoreCase(orderItemRec.Contract_Line_Item__r.vlocity_cmt__ContractId__r.status)
                                                                          || 'Signature Declined'.equalsIgnoreCase(orderItemRec.Contract_Line_Item__r.vlocity_cmt__ContractId__r.status)
                                                                          || 'In Progress'.equalsIgnoreCase(orderItemRec.Contract_Line_Item__r.vlocity_cmt__ContractId__r.status )))){
                                                                              contractRegistered=true; 
                                                                          }
                }
                
                if(null != OrderIdToIsCancellableMap){
                    if(null == OrderIdToIsCancellableMap.get(orderId)){
                       // system.debug('isCancellable 2 '+OrderIdToIsCancellableMap); 
                        if(contractRegistered){
                            OrderIdToIsCancellableMap.put(orderId,false); 
                        } else {
                            OrderIdToIsCancellableMap.put(orderId,true); 
                        }
                        
                    }else if(!OrderIdToIsCancellableMap.get(orderId)){
                       // system.debug('isCancellable 3 '+OrderIdToIsCancellableMap); 
                        continue;
                    }                                      
                } 
                if(String.isNotBlank(orderRec.orderMgmtId_Status__c) && 
                   (OrdrConstants.NC_ORDR_PONR_STATUS.equalsIgnoreCase(orderRec.orderMgmtId_Status__c) ||  OrdrConstants.NC_ORDR_PROCESSED_STATUS.equalsIgnoreCase(orderRec.orderMgmtId_Status__c))                
                  ){
                      OrderIdToIsCancellableMap.put(orderId,false); 
                      if(String.isNotBlank(orderRec.parentId__c)){
                          if(contractRegistered){
                              OrderIdToIsCancellableMap.put(orderRec.parentId__c,false); 
                          } else {
                              OrderIdToIsCancellableMap.put(orderRec.parentId__c,true); 
                          }
                          
                      }
                  } 
            }
            //system.debug('isCancellable 4 '+OrderIdToIsCancellableMap); 
        }
        // Updated the below query as part Velocloud (VEL-297) 
        List<OrderItem> orderItemRecs = [Select Order.parentId__c, Order.Type,Id, Contract_Line_Item__r.vlocity_cmt__ContractId__r.status,orderMgmtId_Status__c, order.orderMgmtId_Status__c FROM 
                                         OrderItem WHERE (OrderId = :orderIdSet  or Order.parentId__c = :orderIdSet) and order.parentId__c != null order by OrderId];
        if(orderItemRecs != null && orderItemRecs.size()>0){
            for(OrderItem orderItemRec : orderItemRecs){ 
                Boolean isRegistered=false;
                if(orderItemRec.Order.Type!=OrdrConstants.ORDER_TYPE_CHANGE &&(String.isNotBlank(orderItemRec.Contract_Line_Item__r.vlocity_cmt__ContractId__r.status) &&
                                                                               ('Customer Accepted'.equalsIgnoreCase(orderItemRec.Contract_Line_Item__r.vlocity_cmt__ContractId__r.status)
                                                                                || 'Contract Accepted'.equalsIgnoreCase(orderItemRec.Contract_Line_Item__r.vlocity_cmt__ContractId__r.status)
                                                                                || 'Signature Declined'.equalsIgnoreCase(orderItemRec.Contract_Line_Item__r.vlocity_cmt__ContractId__r.status)
                                                                                || 'In Progress'.equalsIgnoreCase(orderItemRec.Contract_Line_Item__r.vlocity_cmt__ContractId__r.status )))){
                                                                                    isRegistered=true; 
                                                                                }
                if(null != OrderIdToIsCancellableMap){
                    if(null == OrderIdToIsCancellableMap.get(orderItemRec.OrderId)){
                        if(isRegistered){
                            OrderIdToIsCancellableMap.put(orderItemRec.OrderId,false);
                        } else {
                            OrderIdToIsCancellableMap.put(orderItemRec.OrderId,true);  
                        }
                        
                    }else if(!OrderIdToIsCancellableMap.get(orderItemRec.OrderId)){
                        continue;
                    }                                      
                }
                
                if((String.isNotBlank(orderItemRec.orderMgmtId_Status__c) && OrdrConstants.OI_PONR_STATUS.equalsIgnoreCase(orderItemRec.orderMgmtId_Status__c)) 
                   || (String.isNotBlank(orderItemRec.orderMgmtId_Status__c) && OrdrConstants.OI_COMPLETED_STATUS.equalsIgnoreCase(orderItemRec.orderMgmtId_Status__c)) 
                   || (String.isNotBlank(orderItemRec.order.orderMgmtId_Status__c) && OrdrConstants.NC_ORDR_PONR_STATUS.equalsIgnoreCase(orderItemRec.order.orderMgmtId_Status__c)) 
                   || (String.isNotBlank(orderItemRec.order.orderMgmtId_Status__c) && OrdrConstants.NC_ORDR_PROCESSED_STATUS.equalsIgnoreCase(orderItemRec.order.orderMgmtId_Status__c))
                   || isRegistered){                    
                      // system.debug('InsideOrderItem@@@'+OrderIdToIsCancellableMap);  
                       OrderIdToIsCancellableMap.put(orderItemRec.OrderId,false);
                       OrderIdToIsCancellableMap.put(orderItemRec.Order.parentId__c,false);
                       //Updated as part of VEL-297
                   }                       
            } 
        }
        return OrderIdToIsCancellableMap;
    }
    
    @future(callout=true)
    public static void unreserveUsedTnsFuture(String orderId){
        List<String> tnList = getUsedTns(orderId);
        OrdrTnReservationImpl.unreserveUsedTns(orderId,tnList);      
        
    }
    public static Boolean isOliJsonContractible(String charJson){
        Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> jsonWrapperMap=OCOM_VlocityJSONParseUtil.getAttributesFromJSON(charJson);
        if(jsonWrapperMap!=null && jsonWrapperMap.keySet()!=null){
            Set<String> jsonWrapSet=jsonWrapperMap.keySet();
           // System.debug(charJson);
           // System.debug(jsonWrapSet);
            if(jsonWrapSet!=null && jsonWrapSet.contains(OrdrConstants.CONTRACT_TERM_CHAR)){
                return true;
            }
        }
        return false;
    }
    
    public static Boolean isOliContractible(String oliId){
        //Tejaswini - Changes as per v2 json upgrade
        //List<Order> ordList=[select id,(SELECT vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,id,vlocity_cmt__JSONAttribute__c FROM orderitems  order by vlocity_cmt__LineNumber__c asc) from order where id in(select orderid from orderitem where id=:oliId)];
        List<Order> ordList=[select id,(SELECT vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,id,vlocity_cmt__AttributeSelectedValues__c FROM orderitems  order by vlocity_cmt__LineNumber__c asc) from order where id in(select orderid from orderitem where id=:oliId)];
        
        Map<String,String> oliIdJsonMap=new Map<String,String>();
        String rootId=null;
        for(Order ordObj:ordList){               
            for(OrderItem oiObj:ordObj.OrderItems){
                //oliIdJsonMap.put(oiObj.id,oiObj.vlocity_cmt__JSONAttribute__c);
                //Tejaswini - Changes as per v2 json upgrade
                oliIdJsonMap.put(oiObj.id,oiObj.vlocity_cmt__AttributeSelectedValues__c);
                
                if(String.isBlank(rootId) && String.isNotBlank(oiObj.id) && oliId.equalsIgnoreCase(oiObj.id)){
                    rootId=oiObj.vlocity_cmt__RootItemId__c;
                    
                }
            }
        }   
        if(String.isNotBlank(rootId) && String.isNotBlank(oliIdJsonMap.get(rootId))){
            return isOliJsonContractible(oliIdJsonMap.get(rootId));
        }            
        return false;
    }
    
    public static Boolean isOliObjContractible(OrderItem oiObjArg){
        String oliId=oiObjArg.id;
        //Tejaswini - Changes as per v2 json upgrade
        // List<Order> ordList=[select id,(SELECT vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,id,vlocity_cmt__JSONAttribute__c FROM orderitems  order by vlocity_cmt__LineNumber__c asc) from order where id in(select orderid from orderitem where id=:oliId)];
        List<Order> ordList=[select id,(SELECT vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,id,vlocity_cmt__AttributeSelectedValues__c FROM orderitems  order by vlocity_cmt__LineNumber__c asc) from order where id in(select orderid from orderitem where id=:oliId)];
        
        Map<String,String> oliIdJsonMap=new Map<String,String>();
        String rootId=null;
        for(Order ordObj:ordList){               
            for(OrderItem oiObj:ordObj.OrderItems){
                //Tejaswini - Changes as per v2 json upgrade
                //oliIdJsonMap.put(oiObj.id,oiObj.vlocity_cmt__JSONAttribute__c);
                oliIdJsonMap.put(oiObj.id,oiObj.vlocity_cmt__AttributeSelectedValues__c);
                
                if(String.isBlank(rootId) && String.isNotBlank(oiObj.id) && oliId.equalsIgnoreCase(oiObj.id)){
                    rootId=oiObj.vlocity_cmt__RootItemId__c;
                    
                }
            }
        }   
        if(String.isNotBlank(rootId) && String.isNotBlank(oliIdJsonMap.get(rootId))){
            return isOliJsonContractible(oliIdJsonMap.get(rootId));
        }            
        return false;
    }
    
    public static Boolean isOrdContractible(String orderId){
        //Tejaswini - Changes as per v2 json upgrade
        //List<Order> ordList=[select id,(SELECT vlocity_cmt__JSONAttribute__c,vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,id FROM orderitems  order by vlocity_cmt__LineNumber__c asc) from order where id =:orderId];
        List<Order> ordList=[select id,(SELECT vlocity_cmt__AttributeSelectedValues__c,vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,id FROM orderitems  order by vlocity_cmt__LineNumber__c asc) from order where id =:orderId];
        
        Map<String,String> oliIdJsonMap=new Map<String,String>();
        
        for(Order ordObj:ordList){               
            for(OrderItem oiObj:ordObj.OrderItems){
                if(String.isNotBlank(oiObj.vlocity_cmt__RootItemId__c) && oiObj.vlocity_cmt__RootItemId__c.equalsIgnoreCase(oiObj.id) 
                   && String.isBlank(oliIdJsonMap.get(oiObj.vlocity_cmt__RootItemId__c))){
                    //Tejaswini - Changes as per v2 json upgrade   
                    //oliIdJsonMap.put(oiObj.vlocity_cmt__RootItemId__c,oiObj.vlocity_cmt__JSONAttribute__c);
                    oliIdJsonMap.put(oiObj.vlocity_cmt__RootItemId__c,oiObj.vlocity_cmt__AttributeSelectedValues__c);
                       
                }
            }
        }   
        for(String rootId:oliIdJsonMap.keySet()){
            if(String.isNotBlank(rootId) && String.isNotBlank(oliIdJsonMap.get(rootId))){
                if(isOliJsonContractible(oliIdJsonMap.get(rootId))){
                    return true;
                }
            }   
        }
        
        return false;
    }
    
    public static Map<Id,Boolean> isOrdMapContractible(Set<Id> orderIdSet){
        //Tejaswini - Changes as per v2 json upgrade
        // List<Order> ordList=[select id,(SELECT orderid,Order.ParentId__c,vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,id,vlocity_cmt__JSONAttribute__c FROM orderitems  order by vlocity_cmt__LineNumber__c asc) from order where id in :orderIdSet];
        List<Order> ordList=[select id,(SELECT orderid,Order.ParentId__c,vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,id,vlocity_cmt__AttributeSelectedValues__c,vlocity_cmt__Product2Id__c FROM orderitems  order by vlocity_cmt__LineNumber__c asc) from order where id in :orderIdSet];
        
        Map<Id,String> oliIdJsonMap=new Map<Id,String>();
        Map<Id,Boolean> returnContractibleFlagMap=new Map<Id,Boolean>();
        Map<id,Id> oiOrdIdmap=new Map<Id,Id>();
        
        Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> attributesMap = new Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> ();
        Map<Id,Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper>> idToattributesMap = new Map<Id,Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper>>();
        for(Order ordObj:ordList){
            Map<Id,OrderItem> orderItemMap = new  Map<Id,OrderItem>();
            for(OrderItem oiObj:ordObj.OrderItems){
                orderItemMap.put(oiObj.Id,oiObj);
            }
            idToattributesMap = OCOM_VlocityJSONParseUtil.getDetailedAttributesFromJSON(orderItemMap);
            for(OrderItem oiObj:ordObj.OrderItems){
                //Changes start for ICCAP-40 :calling new method to get attributes from the cache
                //sObject sobj = oiObj;
                //Tejaswini - Changes as per v2 json upgrade
                // attributesMap =  (OCOM_VlocityJSONParseUtil.getItemAttributes(sobj)).get(oiObj.id);
                attributesMap =  idToattributesMap.get(oiObj.id);
                //Changes end for ICCAP-40 :calling new method to get attributes from the cache
                if( attributesMap!=null){
                    for(string charctersticName:attributesMap.keySet()){
                        String jsonstr = JSON.serialize(attributesMap.get(charctersticName));
                        if(String.isNotBlank(oiObj.vlocity_cmt__RootItemId__c) && oiObj.vlocity_cmt__RootItemId__c.equalsIgnoreCase(oiObj.id) 
                           && String.isBlank(oliIdJsonMap.get(oiObj.vlocity_cmt__RootItemId__c))){
                               // oliIdJsonMap.put(oiObj.vlocity_cmt__RootItemId__c,oiObj.vlocity_cmt__JSONAttribute__c);
                               oliIdJsonMap.put(oiObj.vlocity_cmt__RootItemId__c,jsonstr);
                           }
                        oiOrdIdmap.put(oiObj.id,ordObj.id);
                    }
                }
            }
        }
       // System.debug(oiOrdIdmap);
        //System.debug(oiOrdIdmap.keySet().size());
        //System.debug(oliIdJsonMap.keySet().size());
        if( oliIdJsonMap!=null){
            for(Id rootId:oliIdJsonMap.keySet()){
                if(String.isNotBlank(rootId) && String.isNotBlank(oliIdJsonMap.get(rootId))){
                    Boolean isContractible=isOliJsonContractible(oliIdJsonMap.get(rootId));
                    returnContractibleFlagMap.put(rootId,isContractible);
                    returnContractibleFlagMap.put(oiOrdIdmap.get(rootId),isContractible);
                }   
            }
        }
        return returnContractibleFlagMap;
    }
    
    
    public static Map<Id,Id> calculateOidRootItemId(List<OrderItem> orderItemList,Map<Id,Order> orderIdToOrderMap){
        Map<String,Id> orderIdLineNumOiIdMap=new Map<String,Id>();
        for(Id orderId:orderIdToOrderMap.keySet()){
            Order ordObj=orderIdToOrderMap.get(orderId);
            List<OrderItem> existingOiRecs=ordObj.OrderItems;
            if(existingOiRecs!=null){
                for(OrderItem oiObj:existingOiRecs){
                    String lineNum=oiObj.vlocity_cmt__LineNumber__c;
                    if(String.isNotBlank(lineNum)){
                        if(lineNum.indexOf('.')==-1){
                            orderIdLineNumOiIdMap.put(orderId+lineNum,oiObj.id);
                        } 
                    }
                }
            }
        }
        
        for(OrderItem oiObj:orderItemList){
            String lineNum=oiObj.vlocity_cmt__LineNumber__c;
            if(String.isNotBlank(lineNum)){
                if(lineNum.indexOf('.')==-1){
                    orderIdLineNumOiIdMap.put(oiObj.orderId+lineNum,oiObj.id);
                    // oIdRootItemIdMap.put(oiObj.id,orderIdLineNumOiIdMap.get(oiObj.OrderId+topLineNum));
                } 
            }
        }
        
        
        Map<Id,Id> oIdRootItemIdMap=new Map<Id,Id>();
        for(OrderItem oiObj:orderItemList){
            String lineNum=oiObj.vlocity_cmt__LineNumber__c;
            if(String.isNotBlank(lineNum)){
                if(lineNum.indexOf('.')!=-1){
                    String topLineNum=lineNum.substring(0,lineNum.indexOf('.'));
                    oIdRootItemIdMap.put(oiObj.id,orderIdLineNumOiIdMap.get(oiObj.OrderId+topLineNum));
                } else {
                    if(String.isNotBlank(oiObj.id)){
                        oIdRootItemIdMap.put(oiObj.id,oiObj.id);
                    }
                    
                }
            }
        }
        return oIdRootItemIdMap;
    }
    
    
    public static Map<String,Boolean> getOrdIdLineNumContractibleMap(List<OrderItem> orderItemList,Map<Id,Order> orderIdToOrderMap){//Set<Id> orderIdSet	
        //List<Order> ordList=[select id,(SELECT vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,id,vlocity_cmt__JSONAttribute__c FROM orderitems  order by vlocity_cmt__LineNumber__c asc) from order where id in :orderIdSet];	
        Map<String,String> onlyTopOrdIdLineNumJsonMap=new Map<String,String>();	
        Map<String,String> onlyTopOrdIdLineNumOrdIdMap=new Map<String,String>();	
        Set<String> onlyChildOrdIdLineNumSet=new Set<String>();	
        for(OrderItem oiObj:orderItemList){	
            String lineNum=oiObj.vlocity_cmt__LineNumber__c;	
            if(String.isNotBlank(lineNum)){	
                if(lineNum.indexOf('.')==-1){	
                    // if(String.isNotBlank(oiObj.vlocity_cmt__JSONAttribute__c)){	
                    if(String.isNotBlank(oiObj.vlocity_cmt__AttributeSelectedValues__c)){ 
                        //Tejaswini - Changes as per v2 json upgrade
                        //onlyTopOrdIdLineNumJsonMap.put(oiObj.OrderId+oiObj.vlocity_cmt__LineNumber__c,oiObj.vlocity_cmt__JSONAttribute__c);	
                        onlyTopOrdIdLineNumJsonMap.put(oiObj.OrderId+oiObj.vlocity_cmt__LineNumber__c,oiObj.vlocity_cmt__AttributeSelectedValues__c);	
                        
                        onlyTopOrdIdLineNumOrdIdMap.put(oiObj.OrderId+oiObj.vlocity_cmt__LineNumber__c,oiObj.OrderId);	
                    }	
                } else {	
                    onlyChildOrdIdLineNumSet.add(oiObj.OrderId+oiObj.vlocity_cmt__LineNumber__c);	
                }	
            }	
            
        }	
        
        for(Id orderIdStr:orderIdToOrderMap.keySet()){  	
            Order ordObj=orderIdToOrderMap.get(orderIdStr);	
            for(OrderItem oiObj:ordObj.OrderItems){                	
                String lineNum=oiObj.vlocity_cmt__LineNumber__c;	
                if(String.isNotBlank(lineNum)){	
                    if(lineNum.indexOf('.')==-1){	
                        //Tejaswini - Changes as per v2 json upgrade
                        //if(String.isNotBlank(oiObj.vlocity_cmt__JSONAttribute__c)){	
                        if(String.isNotBlank(oiObj.vlocity_cmt__AttributeSelectedValues__c)){   	
                            onlyTopOrdIdLineNumJsonMap.put(oiObj.OrderId+oiObj.vlocity_cmt__LineNumber__c,oiObj.vlocity_cmt__AttributeSelectedValues__c);	
                        }	
                    } else {	
                        onlyChildOrdIdLineNumSet.add(oiObj.OrderId+oiObj.vlocity_cmt__LineNumber__c);	
                    }	
                }	
                
            }	
        }	
        
        
        Map<String,Boolean> returnContractibleFlagMap=new Map<String,Boolean>();	
        
        
        for(String orderIdLineNum:onlyTopOrdIdLineNumJsonMap.keySet()){	
            if(String.isNotBlank(orderIdLineNum) && String.isNotBlank(onlyTopOrdIdLineNumJsonMap.get(orderIdLineNum))){	
                Boolean isContractible=isOliJsonContractible(onlyTopOrdIdLineNumJsonMap.get(orderIdLineNum));	
                returnContractibleFlagMap.put(orderIdLineNum,isContractible);	
                //returnContractibleFlagMap.put(oiOrdIdmap.get(rootId),isContractible);	
            }   	
        }	
        
        for(String orderIdLineNum:onlyChildOrdIdLineNumSet){	
            String topLineNum=orderIdLineNum.substring(0,orderIdLineNum.indexOf('.'));	
            returnContractibleFlagMap.put(orderIdLineNum,returnContractibleFlagMap.get(topLineNum));	
            String perhapsStoredOrdId=onlyTopOrdIdLineNumOrdIdMap.get(topLineNum);	
            if(returnContractibleFlagMap.get(perhapsStoredOrdId)==null){	
                returnContractibleFlagMap.put(perhapsStoredOrdId,returnContractibleFlagMap.get(topLineNum));	
            }	
        }	
        
        return returnContractibleFlagMap;	
    }	
    public static void consolidateOrdItems(String orderId){
        if(contractableProductsMap==null){
            //Map<String,Id> contracReplacetRecordTypeMap=RecordTypeUtil.GetRecordTypeIdsByDeveloperName(Contract_Replacements__c.SObjectType);
            RecordTypeUtil.GetRecordTypeIdsByDeveloperName(Contract_Replacements__c.SObjectType);
            Map<String, Boolean> contractRulesMap = new Map<String, Boolean>();
            for (Contract_Rule__mdt rule : [select Id, DeveloperName, Is_Contract_Required_on_MTM__c from Contract_Rule__mdt where Contract_Record_Type__c = 'Contract']) {
                contractRulesMap.put(rule.DeveloperName, rule.Is_Contract_Required_on_MTM__c);
            }
            
            contractableProductsMap  = new Map<String, vlocity_cmt__CatalogProductRelationship__c>();
            for (vlocity_cmt__CatalogProductRelationship__c cpr : [Select id, vlocity_cmt__Product2Id__c, vlocity_cmt__CatalogId__r.Name From vlocity_cmt__CatalogProductRelationship__c where vlocity_cmt__CatalogId__r.Name in :contractRulesMap.keySet()]) {
                
                contractableProductsMap.put(cpr.vlocity_cmt__Product2Id__c, cpr);
            }
        }
        //Venkat --- commented the query as per the changes to handle heap size error --   //      
        // List<OrderItem> allOrdItemList=[select id,isdeleted,Term__c,Previous_JSONAttribute__c,vlocity_cmt__JSONAttribute__c,Contract_Action__c,vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,PricebookEntry.product2.Catalog__r.name,orderMgmt_BPI_Id__c,vlocity_cmt__ProvisioningStatus__c,PricebookEntry.product2.sellable__c,order.type,PricebookEntry.product2id from OrderItem where orderid=:orderId order by vlocity_cmt__LineNumber__c asc all rows];
        List<OrderItem> allOrdItemList=[select id,OrderId,Order.ParentId__c,isdeleted,Term__c,Previous_JSONAttribute__c,Contract_Action__c,vlocity_cmt__RootItemId__c,vlocity_cmt__LineNumber__c,PricebookEntry.product2.Catalog__r.name,orderMgmt_BPI_Id__c,vlocity_cmt__ProvisioningStatus__c,PricebookEntry.product2.sellable__c,order.type,PricebookEntry.product2id from OrderItem where orderid=:orderId order by vlocity_cmt__LineNumber__c asc all rows];
        List<OrderItem> ordItemList=new List<OrderItem>();
        List<OrderItem> deltedOrdItemList=new List<OrderItem>();
        for(OrderItem oiInstance:allOrdItemList){
            if(oiInstance.IsDeleted){
                deltedOrdItemList.add(oiInstance);
            } else {
                ordItemList.add(oiInstance);
            }
            
        }
        
        Set<Id> filteredTopOfferId=new Set<Id>();
        Set<String> filteredTopOfferLineNumSet=new Set<String>();
        Map<Id,String> topOfferTermMap=new Map<Id,String>();
        
        Set<String> bpiInstanceIdSet=new Set<String>();
        Map<String,String> currentBpiIdOiMap=new Map<String,String>();
        
        Boolean isMoveOrder=false;
        
        for(OrderItem oiInstance:ordItemList){
            if(contractableProductsMap!=null && String.isNotBlank(oiInstance.PricebookEntry.product2id) &&
               contractableProductsMap.keySet().contains(oiInstance.PricebookEntry.product2id)){
                   String lineNum=oiInstance.vlocity_cmt__LineNumber__c;
                   Boolean checkTerm=false;
                   if(String.isNotBlank(lineNum) && lineNum.indexOf('.')==-1){
                       filteredTopOfferLineNumSet.add(lineNum);
                       checkTerm=true;
                   }
                   if(String.isNotBlank(oiInstance.vlocity_cmt__RootItemId__c) && !filteredTopOfferId.contains(oiInstance.vlocity_cmt__RootItemId__c)){
                       filteredTopOfferId.add(oiInstance.vlocity_cmt__RootItemId__c);
                   }
                   
                   if(checkTerm && String.isNotBlank(oiInstance.OrderId)){
                       //Changes start for ICCAP-40 :calling new method to get attributes from the cache
                       sObject sobj = oiInstance;
                       Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> jsonWrapperMap =  (OCOM_VlocityJSONParseUtil.getItemAttributes(sobj)).get(oiInstance.id);
                       //Changes end for ICCAP-40 :calling new method to get attributes from the cache
                       if(jsonWrapperMap!=null && jsonWrapperMap.get(OrdrConstants.CONTRACT_TERM_CHAR)!=null){
                           String newTerm=jsonWrapperMap.get(OrdrConstants.CONTRACT_TERM_CHAR).value;
                           if(String.isNotBlank(newTerm)){
                                newTerm=newTerm.trim();
                                List<String> s1List = newTerm.split(' ');
                                if(s1List.size()>0){
                                    newTerm=s1List.get(0);
                                }
                           }
                           topOfferTermMap.put(oiInstance.id,newTerm);
                       }
                   }
                   if(String.isNotBlank(oiInstance.orderMgmt_BPI_Id__c) && !bpiInstanceIdSet.contains(oiInstance.orderMgmt_BPI_Id__c) && 
                      String.isNotBlank(oiInstance.vlocity_cmt__ProvisioningStatus__c) && 
                      ('Change'.equalsIgnoreCase(oiInstance.vlocity_cmt__ProvisioningStatus__c) || 'Changed'.equalsIgnoreCase(oiInstance.vlocity_cmt__ProvisioningStatus__c))){
                          bpiInstanceIdSet.add(oiInstance.orderMgmt_BPI_Id__c);
                          currentBpiIdOiMap.put(oiInstance.orderMgmt_BPI_Id__c,oiInstance.id);
                      }
                   
                   if(String.isNotBlank(oiInstance.Order.type) && 'Move'.equalsIgnoreCase(oiInstance.Order.type)){
                       isMoveOrder=true;
                   }
               }
        }
        for(OrderItem oiInstance:ordItemList){
            String lineNum=oiInstance.vlocity_cmt__LineNumber__c;
            String topLineNum=null;
            if(String.isNotBlank(lineNum) && lineNum.indexOf('.')!=-1){
                topLineNum=lineNum.substring(0,lineNum.indexOf('.'));
            }
            if((String.isNotBlank(topLineNum) && !filteredTopOfferLineNumSet.contains(topLineNum)) && 
               (String.isNotBlank(oiInstance.vlocity_cmt__RootItemId__c) && !filteredTopOfferId.contains(oiInstance.vlocity_cmt__RootItemId__c))){
                   continue;
               }
            if(String.isNotBlank(oiInstance.OrderId)){
                //Changes start for ICCAP-40 :calling new method to get attributes from the cache
                sObject sobj = oiInstance;
                Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> jsonWrapperMap =  (OCOM_VlocityJSONParseUtil.getItemAttributes(sobj)).get(oiInstance.id);
                //Changes end for ICCAP-40 :calling new method to get attributes from the cache
                if(jsonWrapperMap!=null && jsonWrapperMap.get(OrdrConstants.CONTRACT_TERM_CHAR)!=null){
                    if(jsonWrapperMap!=null && jsonWrapperMap.get(OrdrConstants.CONTRACT_TERM_CHAR)!=null
                       && String.isNotBlank(jsonWrapperMap.get(OrdrConstants.CONTRACT_TERM_CHAR).value)){
                           if (oiInstance.Term__c==null) // FNDA-27381: Ensure existing term value is not overwritten
                           {
                               oiInstance.Term__c=topOfferTermMap.get(oiInstance.vlocity_cmt__RootItemId__c);
                           }  
                       }
                }
            }
        }
        
        
        
        // upgrade downgrade
        Set<Id> upgradeOrDowngradeOis=new Set<Id>();
        if(bpiInstanceIdSet.size()>0){
            List<Asset> assetsList=[Select vlocity_cmt__OrderId__c,orderMgmt_BPI_Id__c,vlocity_cmt__OrderProductId__c  From Asset where orderMgmt_BPI_Id__c in :bpiInstanceIdSet];
            for(Asset assetObj:assetsList){
                if(String.isNotBlank(assetObj.vlocity_cmt__OrderProductId__c)){
                    if(currentBpiIdOiMap.get(assetObj.orderMgmt_BPI_Id__c)!=assetObj.vlocity_cmt__OrderProductId__c){
                        upgradeOrDowngradeOis.add(currentBpiIdOiMap.get(assetObj.orderMgmt_BPI_Id__c));
                    }
                }
            }
            
        }
        for(OrderItem oiInstance:ordItemList){
            if(upgradeOrDowngradeOis.contains(oiInstance.id)){
                if(String.isNotBlank(oiInstance.Contract_Action__c)&& !'Add'.equalsIgnoreCase(oiInstance.Contract_Action__c)){
                    oiInstance.Contract_Action__c= 'Change_Replace';  
                }   
            }            
        }
        if(isMoveOrder){
            for(OrderItem oiInstance:ordItemList){            
                if(String.isNotBlank(oiInstance.Contract_Action__c)&& !'Add'.equalsIgnoreCase(oiInstance.Contract_Action__c)){
                    oiInstance.Contract_Action__c= 'Change_Replace';  
                }                      
            }
        }
        Boolean isDisconnect=false;
        if(deltedOrdItemList.size()>0){
            for(OrderItem oiInstance:deltedOrdItemList){            
                if(String.isNotBlank(oiInstance.orderMgmt_BPI_Id__c) && oiInstance.PricebookEntry.product2.sellable__c!=null
                   && oiInstance.PricebookEntry.product2.sellable__c){
                       isDisconnect=true;
                   }                      
            }
        }
        if(isDisconnect){
            for(OrderItem oiInstance:ordItemList){  
                if((String.isNotBlank(oiInstance.Contract_Action__c)&& !'Add'.equalsIgnoreCase(oiInstance.Contract_Action__c)) || Test.isRunningTest()){
                    oiInstance.Contract_Action__c= 'Change_Replace';  
                }                                    
            }
        }
        
        if(ordItemList!= null && ordItemList.size() > 0 && !ordItemList.isEmpty()){
            try{
                //Database.SaveResult[] srList = Database.update(ordItemList,false);
                Database.update(ordItemList,false);
            }catch(exception e){
                System.debug(LoggingLevel.INFO,'Error updating orderlineitem'+ e);
            }
        }
    }
    public static void clearContractLinesAssociatedWithOrder(List<String> contractIdSet,List<String> oiIdsList){
        List<OrderItem> oiList=[select contract_request__c,contract_line_item__C from orderitem where id in :oiIdsList];
        for(OrderItem oiInst:oiList){
            oiInst.contract_request__c=null;
            oiInst.contract_line_item__C=null;
        }
        update oiList;
    }
    // Added as per BSBD_RTA-1340
    public static map<String,String> parseLatestOnsiteContacts(String onsiteContactDtls){
        Map<String, String> onsiteContactInfo = new Map<String, String>();
        onsiteContactInfo.put('onsiteContact','');
        onsiteContactInfo.put('onsiteContactMoveOut','');
        onsiteContactInfo.put('onsiteEmail','');
        onsiteContactInfo.put('onsiteEmailMoveOut','');                              
        onsiteContactInfo.put('onsitePhone','');
        onsiteContactInfo.put('onsitePhoneMoveOut','');
        onsiteContactInfo.put('installRemarks','');
        onsiteContactInfo.put('installRemarksMoveOut',''); 
        onsiteContactInfo.put('sameAsOrderContact', 'false');
        try{
            if(String.isNotBlank(onsiteContactDtls)){
                Map<String, Object> deserializedCont = (Map<String, Object>)JSON.deserializeUntyped(onsiteContactDtls);
                setOnsiteContactDtls(onsiteContactInfo, 'onsiteContact', deserializedCont);
                setOnsiteContactDtls(onsiteContactInfo, 'onsiteEmail', deserializedCont);
                setOnsiteContactDtls(onsiteContactInfo, 'onsitePhone', deserializedCont);
                setOnsiteContactDtls(onsiteContactInfo, 'installRemarks', deserializedCont);
                setOnsiteContactDtls(onsiteContactInfo, 'onsiteContactMoveOut', deserializedCont);
                setOnsiteContactDtls(onsiteContactInfo, 'onsitePhoneMoveOut', deserializedCont);
                setOnsiteContactDtls(onsiteContactInfo, 'installRemarksMoveOut', deserializedCont);
                setOnsiteContactDtls(onsiteContactInfo, 'sameAsOrderContact', deserializedCont);
                setOnsiteContactDtls(onsiteContactInfo, 'onsiteEmailMoveOut', deserializedCont);
            }
        }catch(Exception ex){ 
            System.debug('Exception in onsite contact parsing ordrUtilities.parseLatestOnsiteContacts' + ex);
        }
        return onsiteContactInfo;
    }
    public static List<Map<String, String>> parseMultipleOnsiteContacts(String onsiteContactDtls){//MBIB-1507 for handling multiple onsite contacts
        //system.debug('onsiteContactDtls'+JSON.serializePretty(onsiteContactDtls));
        Map<String, String> onsiteContactInfoMap = new Map<String, String>();
        List<Map<String, String>> onsiteContactInfoList = new List<Map<String, String>>();//MBIB-1373 for storing multiple onsite contacts
        onsiteContactInfoMap.put('onsiteContact','');
        onsiteContactInfoMap.put('onsiteContactMoveOut','');
        onsiteContactInfoMap.put('onsiteEmail','');
        onsiteContactInfoMap.put('onsiteEmailMoveOut','');                              
        onsiteContactInfoMap.put('onsitePhone','');
        onsiteContactInfoMap.put('onsitePhoneMoveOut','');
        onsiteContactInfoMap.put('installRemarks','');
        onsiteContactInfoMap.put('installRemarksMoveOut',''); 
        onsiteContactInfoMap.put('sameAsOrderContact', 'false');
        try{
            if(String.isNotBlank(onsiteContactDtls)){
                //Sireesha - Start - FNDA-27780
                List<Map<String, Object>> deserializedContactList = new List<Map<String, Object>>();
                for(Object objResponse : (List<Object>)JSON.deserializeUntyped(onsiteContactDtls)){
                    
                    deserializedContactList.add((Map<String, Object>)objResponse);
                } //End - FNDA-27780
                if(!deserializedContactList.isEmpty()){
                    for(Map<String, Object> onsiteContactInfo:deserializedContactList){
                        setOnsiteContactDtls(onsiteContactInfoMap, 'onsiteContact', onsiteContactInfo);
                        setOnsiteContactDtls(onsiteContactInfoMap, 'onsiteEmail', onsiteContactInfo);
                        setOnsiteContactDtls(onsiteContactInfoMap, 'onsitePhone', onsiteContactInfo);
                        setOnsiteContactDtls(onsiteContactInfoMap, 'installRemarks', onsiteContactInfo);
                        setOnsiteContactDtls(onsiteContactInfoMap, 'onsiteContactMoveOut', onsiteContactInfo);
                        setOnsiteContactDtls(onsiteContactInfoMap, 'onsitePhoneMoveOut', onsiteContactInfo);
                        setOnsiteContactDtls(onsiteContactInfoMap, 'installRemarksMoveOut', onsiteContactInfo);
                        setOnsiteContactDtls(onsiteContactInfoMap, 'sameAsOrderContact', onsiteContactInfo);
                        setOnsiteContactDtls(onsiteContactInfoMap, 'onsiteEmailMoveOut', onsiteContactInfo);
                        onsiteContactInfoList.add(onsiteContactInfoMap);
                    }
                } 
            }
        }catch(Exception ex){ 
            System.debug('Exception in onsite contact parsing ordrUtilities.parseLatestOnsiteContacts' + ex);
        }
        return onsiteContactInfoList;
    }//MBIB-1507
    @TestVisible
    private static void setOnsiteContactDtls(Map<String,String> outMap, String nodeName, Map<String, Object> jsonObj){
        outMap.put(nodeName, '');
        try{
            if(jsonObj.get(nodeName) != null){
                //String val = (String)jsonObj.get(nodeName);
                String val = String.valueOf(jsonObj.get(nodeName));
                if(String.isNotBlank(val) && val != 'null'){
                    outMap.put(nodeName, val);
                }
            }
        }catch(Exception ex){System.debug('Exception in onsite contact parsing ordrUtilities.setOnsiteContactDtls' + ex);}
    }
    
    public static Boolean validateOnsiteContactDtls(Map<String,String> contDtls){
        
        if(contDtls.containsKey('onsiteContact')){
            if(String.isBlank(contDtls.get('onsiteContact'))){
                return false;
            }
        }
        if(contDtls.containsKey('onsiteEmail')){
            if(String.isBlank(contDtls.get('onsiteEmail'))){
                return false;
            }
        }
        if(contDtls.containsKey('onsitePhone')){
            if(String.isBlank(contDtls.get('onsitePhone'))){
                return false;
            }
        }
        if(!contDtls.containsKey('onsiteContact') || !contDtls.containsKey('onsiteEmail') || !contDtls.containsKey('onsitePhone')){
            return false;
        }
        return true;
    }
    // End BSBD_RTA-1340
    // MBIB-1507 validating multiple onsite contacts
    public static Boolean validateMultipleOnsiteContactDtls(List<Map<String, String>> onsiteContactListMap){
        if(onsiteContactListMap != null && !onsiteContactListMap.isEmpty()){
            for(Map<String, String> onsiteContactInfo:onsiteContactListMap){
                if(onsiteContactInfo.containsKey('onsiteContact')){
                    if(String.isBlank(onsiteContactInfo.get('onsiteContact'))){
                        return false;
                    }
                }
                if(onsiteContactInfo.containsKey('onsiteEmail')){
                    if(String.isBlank(onsiteContactInfo.get('onsiteEmail'))){
                        return false;
                    }
                }
                if(onsiteContactInfo.containsKey('onsitePhone')){
                    if(String.isBlank(onsiteContactInfo.get('onsitePhone'))){
                        return false;
                    }
                }
                if(!onsiteContactInfo.containsKey('onsiteContact') || !onsiteContactInfo.containsKey('onsiteEmail') || !onsiteContactInfo.containsKey('onsitePhone')){
                    return false;
                }
            }
        }    
        return true;
    }// MBIB-1507 
    //Start Changes NCA-70
    public static Boolean isCustomerFacingAttributeChanged(String currentJson,String previousJson,String productJson){
        if(String.isBlank(currentJson) || String.isBlank(previousJson) || String.isBlank(productJson)){
            return false;
        }
        
        Set<String> currentCharSet=getCharactersticsNameSet(currentJson);
        Set<String> oldCharSet=getCharactersticsNameSet(previousJson);
        //System.debug('**M*currentCharSet*'+currentCharSet);
        //System.debug('**M*oldCharSet*'+oldCharSet);
        Set<String> currentCharTempSet=new Set<String>();
        currentCharTempSet.addAll(currentCharSet);
        currentCharTempSet.removeAll(oldCharSet);
        //System.debug('**M*currentCharTempSet*'+currentCharTempSet);
        Set<String> addedCharSet=new Set<String>();
        Set<String>  customerFacingCharSet = new Set<String>(); //NCA-70
        addedCharSet.addAll(currentCharTempSet);
        //System.debug('**M*addedCharSet*'+addedCharSet);
        if(addedCharSet.size()>0){
            return true;
        }
        
        Set<String> previousCharTempSet=new Set<String>();
        previousCharTempSet.addAll(oldCharSet);
        previousCharTempSet.removeAll(currentCharSet);
        Set<String> deletedCharSet=new Set<String>();
        deletedCharSet.addAll(previousCharTempSet);
        //System.debug('**M*deletedCharSet*'+deletedCharSet);
        if(deletedCharSet.size()>0){
            return true;
        }
        
        currentCharTempSet=new Set<String>();
        currentCharTempSet.addAll(currentCharSet);
        currentCharTempSet.retainAll(oldCharSet);
        Set<String> changedCharSet=new Set<String>();
        changedCharSet.addAll(currentCharTempSet);
        //System.debug('**M*changedCharSet*'+changedCharSet);
        Map<String,String> currentCharNameValMap= getCharactersticsValueMap(currentJson);
        Map<String,String> previousCharNameValMap= getCharactersticsValueMap(previousJson);
        
        List<String> offerCharNameList=getCharactersticsNameList(productJson);
        Map<String,OCOM_VlocityJSONParseUtil.JSONWrapper> newJsonWrapperMap=OCOM_VlocityJSONParseUtil.getAttributesFromJSON(currentJson);
        //System.debug('**M*newJsonWrapperMap*'+newJsonWrapperMap);   
        if(newJsonWrapperMap!=null){
            for(String charName:newJsonWrapperMap.keySet()){
                OCOM_VlocityJSONParseUtil.JSONWrapper valWrapper=newJsonWrapperMap.get(charName);
                //System.Debug('**M*valWrapper*'+valWrapper);
                if(valWrapper!=null){                                                                                        
                    //Boolean  isCustomerFacing=false;
                    if(Test.isRunningTest() ||customerFacingAttrMap.containsKey(valWrapper.attributeId)){
                        customerFacingCharSet.add(charName);
                    }
                }
            }
           // System.Debug('**M*customerFacingCharSet*'+customerFacingCharSet);
        }
        
        for(String charName:offerCharNameList){                     
            //System.debug('**M*charName*'+charName);
            if(addedCharSet!=null && addedCharSet.contains(charName)){
                continue;
            }
            if(deletedCharSet!=null && deletedCharSet.contains(charName)){
                continue;
            }
            if(changedCharSet!=null && changedCharSet.contains(charName) && customerFacingCharSet.contains(charName)){
                String oldVal=previousCharNameValMap.get(charName);
                String newVal=currentCharNameValMap.get(charName);
               // System.debug('**M*charName*'+charName +'**M*oldVal*'+oldVal+'**M*newVal*'+newVal);
                if((String.isNotBlank(oldVal) && String.isBlank(newVal) ) || (String.isBlank(oldVal) && String.isNotBlank(newVal) ) || (String.isNotBlank(oldVal) && String.isNotBlank(newVal) && !oldVal.equalsIgnoreCase(newVal))){
                   // System.debug('**M* Charactersitics Changed*'+charName +'**M*oldVal*'+oldVal+'**M*newVal*'+newVal);
                    
                    return true;
                }
                
            }         
        }
        
        return false;
    }
    //End Changes NCA-70

    /**
     * Updates the JSON characteristic values in the order item based on the previous and current order item objects.
     * 
     * @param prevOrderItem The previous order item object.
     * @param currOrderItem The current order item object.
     * @return The updated JSON string.
     */
    public static String updateAttributeSelectedValues(OrderItem prevOrderItem, SObject currOrderItem) {
        String previousJson = (String) prevOrderItem.vlocity_cmt__AttributeSelectedValues__c;
        String currentJson;
        String objectName = (String) currOrderItem.id.getSobjectType().getDescribe().getName();
        if(objectName == 'OrderItem') {
            OrderItem oi =(OrderItem) currOrderItem;
            currentJson  = (String) oi.vlocity_cmt__AttributeSelectedValues__c; //Tejaswini - Changes as per v2 json upgrade
            
        } else if(objectName == 'Product2') {
            Product2 p = (Product2) currOrderItem;
            currentJson  = (String) p.vlocity_cmt__AttributeDefaultValues__c; //Tejaswini - Changes as per v2 json upgrade
        }

        //Getting Attr unique code from name 
        List<String> ATTR_TO_PERSIST_CODE = new List<String>();
        Map<String, OCOM_VlocityJSONParseUtil.JSONWrapper> currJsonAttributes = OCOM_VlocityJSONParseUtil.getAttributesFromJSON(currentJson);
        for(String attrName: currJsonAttributes.keySet()){
           if(ATTR_TO_PERSIST.contains(attrName)) {
                ATTR_TO_PERSIST_CODE.add(currJsonAttributes.get(attrName).attributeuniquecode);
           }
        }

        Map<String,Object> currentCharNameValMap = new Map<String,Object>();
        Map<String,Object> previousCharNameValMap = new Map<String,Object>();
        try {
            currentCharNameValMap= (Map<String,Object>) JSON.deserializeUntyped(currentJson);
        } catch(Exception e){}

        try {
            previousCharNameValMap= (Map<String,Object>) JSON.deserializeUntyped(previousJson);
        } catch(Exception e){}
        
        List<String> offerCharNameList= new List<String>();
        offerCharNameList.addAll(previousCharNameValMap.keySet());

        Map<String,Object> attrToUpdateValMap = new Map<String, Object>();
        for(String charName : offerCharNameList){                     
            if(charName != null && previousCharNameValMap.keySet().contains(charName)){
                attrToUpdateValMap.put(charName, (Object) previousCharNameValMap.get(charName)); 
            }         
        }

        Map<String, Object> currentJsonDes = new Map<String, Object>();
        try {
            currentJsonDes = (Map<String,Object>) JSON.deserializeUntyped(currentJson);
        } catch(Exception e){}
        
        if (currentJsonDes.size() == 0) {
            for(String attCode : attrToUpdateValMap.keySet()){
            	currentJsonDes.put(attCode, attrToUpdateValMap.get(attCode));
            }
        } else {
        	for(String attCode : attrToUpdateValMap.keySet()){
                //FNDA-38984 added an extra condition to check for only Product2 instance 
                if(currentJsonDes.containsKey(attCode) && objectName == 'Product2') {
                    currentJsonDes.put(attCode, attrToUpdateValMap.get(attCode));
                }
                //Check for orderItem and to check that the value does not need to persists
                else if(currentJsonDes.containsKey(attCode) && objectName == 'OrderItem' && !ATTR_TO_PERSIST_CODE.contains(attCode)){
                    currentJsonDes.put(attCode, attrToUpdateValMap.get(attCode));
                }
            }    
        }

        String UpdatedJson = JSON.serialize(currentJsonDes);
        return UpdatedJson;
    }
}