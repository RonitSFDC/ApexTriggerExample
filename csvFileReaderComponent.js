import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import readCSVFile from '@salesforce/apex/CSVFileReader.readCSVFile';

export default class CSVFileReaderComponent extends LightningElement {
    csvFile;
    csvContent;

    handleFileUpload(event) {
        this.csvFile = event.target.files[0];
    }

    handleProcessCSV() {
        if (this.csvFile) {
            let reader = new FileReader();

            reader.onload = (event) => {
                this.csvContent = event.target.result;
                readCSVFile({ csvContent: this.csvContent })
                    .then(result => {
                        // Handle the returned data (result) from Apex
                        console.log('CSV Lines:', result);
                    })
                    .catch(error => {
                        // Handle any errors
                        console.error('Error:', error);
                    });
            }

            reader.readAsText(this.csvFile);
        } else {
            this.showToast('Error', 'Please select a CSV file.', 'error');
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}
