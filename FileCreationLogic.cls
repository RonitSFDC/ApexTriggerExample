//ContentDocumentLink file = [Select Id, ContentDocument.FileType, ContentDocument.LatestPublishedVersion.VersionData from ContentDocumentLink WHERE LinkedEntityId = '0035g00000GKrGmAAL'];
ContentVersion file = [SELECT Title, VersionData FROM ContentVersion WHERE IsLatest = TRUE and ContentDocumentId='0695g00000GoAhBAAV'];
String bodyBase64 = EncodingUtil.base64Encode(file.VersionData);
System.debug('bodyBase64 =>'+ bodyBase64);
System.debug('File =>'+ File);

/*String jsonStr = 'Base64 String';
Attachment attach = new Attachment();
attach.contentType = 'application/pdf';
attach.name = 'myfile.pdf';
attach.parentId = '0035g00000GKrGmAAL';
attach.body = EncodingUtil.base64Decode(jsonStr);
insert attach;*/

//String jsonStr = 'JVBERi0xLjUKJeLjz9MKMSAwIG9iaiAKPDwKL1R5cGUgL0NhdGFsb2cKL09DUHJvcGVydGllcyAKPDwKL09DR3MgWzIgMCBSIDMgMCBSXQovRCAKPDwKL09yZGVyIFsyIDAgUiAzIDAgUl0KL09OIFsyIDAgUiAzIDAgUl0KL1JCR3JvdXBzIFtdCi9PRkYgW10KPj4KPj4KL1BhZ2VzIDQgMCBSCj4+CmVuZG9iaiAKNCAwIG9iaiAKPDwKL0tpZHMgWzUgMCBSXQovVHlwZSAvUGFnZXMKL0NvdW50IDEKPj4KZW5kb2JqIAo1IDAgb2JqIAo8PAovUmVzb3VyY2VzIAo8PAovUHJvcGVydGllcyAKPDwKL1ByNyAzIDAgUgovUHIxMSAyIDAgUgo+PgovRm9udCAKPDwKL0YxOSA2IDAgUgovRjI2IDcgMCBSCi9GMTIgOCAwIFIKL0YzMyA5IDAgUgovRjQwIDEwIDAg';
/*Attachment a = new Attachment(ParentId='0035g00000GKrGmAAL');
//a.contentType = 'application/pdf';
a.body = EncodingUtil.base64Decode(jsonStr);
a.Name = 'Test.pdf';
insert a;*/

Blob blobContent = EncodingUtil.base64Decode(bodyBase64);
ContentVersion objCV = new ContentVersion(
    Title = 'Test',
    PathOnClient = 'test.pdf',
    VersionData = blobContent
);
insert objCV;
objCV = [
    SELECT ContentDocumentId
    FROM ContentVersion
    WHERE Id =: objCV.Id
];
ContentDocumentLink objCDL = new ContentDocumentLink(
    ContentDocumentId = objCV.ContentDocumentId,
    LinkedEntityId = '0035g00000GKrGmAAL',
    Visibility = 'AllUsers'
);
insert objCDL;
