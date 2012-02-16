#include <SPI.h>
#include <Ethernet.h>
#include <SD.h>

/************ ETHERNET STUFF ************/
byte mac[] = { 0x90, 0xA2, 0xDA, 0x00, 0x68, 0xE3 };
byte ip[] = { 129,21,50,26 };
byte gateway[] = { 129,21,50,254 };
char rootFileName[] = "index.htm";
Server server(80);

/************ SDCARD STUFF ************/
Sd2Card card;
SdVolume volume;
SdFile root;
SdFile file;
const int chipSelect = 4;

/************ TIMER STUFF ************/
long previousMillis = 0;
long shortMillis = 0;
long interval = 1800000; //milliseconds. 1800000 == 30 mins


// store error strings in flash to save RAM
#define error(s) error_P(PSTR(s))

void error_P(const char* str) {
  PgmPrint("error: ");
  SerialPrintln_P(str);
  if (card.errorCode()) {
    PgmPrint("SD error: ");
    Serial.print(card.errorCode(), HEX);
    Serial.print(',');
    Serial.println(card.errorData(), HEX);
  }
  while(1);
}

//*********** TEMP CONVERSION ***************
double Thermister(int RawADC) {
  double Temp;
  Temp = log(((512000/RawADC) - 500));
  Temp = 1 / (0.008105004 + (-0.0012558341 + (0.0000127221565 * Temp * Temp ))* Temp );
  Temp = Temp - 273.15;            // Convert Kelvin to Celcius
  Temp = (Temp * 9.0)/ 5.0 + 32.0; // Convert Celcius to Fahrenheit
  Temp = Temp - 10;  //Because this seems to be about the temperature it is too high on a regular basis.
                    //AKA: fuck you math.
  return Temp;
}

String printDouble( double val, unsigned int precision){
// prints val with number of decimal places determine by precision
// NOTE: precision is 1 followed by the number of zeros for the desired number of decimial places
// example: printDouble( 3.1415, 100); // prints 3.14 (two decimal places)

    String retval;
    retval += String(int(val));
    retval += ".";
    unsigned int frac;
    if(val >= 0)
	  frac = (val - int(val)) * precision;
    else
	  frac = (int(val)- val ) * precision;
    retval += frac;
    return retval;
}

//****************************** SETUP ****************************
void setup() {
  Serial.begin(9600);

  PgmPrint("Free RAM: ");
  Serial.println(FreeRam());  
  
  // initialize the SD card at SPI_HALF_SPEED to avoid bus errors with
  // breadboards.  use SPI_FULL_SPEED for better performance.
  pinMode(10, OUTPUT);                       // set the SS pin as an output (necessary!)
  digitalWrite(10, HIGH);                    // but turn off the W5100 chip!

  if (!card.init(SPI_FULL_SPEED, 4)) error("card.init failed!");
  
  // initialize a FAT volume
  if (!volume.init(&card)) error("vol.init failed!");

  PgmPrint("Volume is FAT");
  Serial.println(volume.fatType(),DEC);
  Serial.println();
  
  if (!root.openRoot(&volume)) error("openRoot failed");
  /*
  // list file in root with date and size
  PgmPrintln("Files found in root:");
  root.ls(LS_DATE | LS_SIZE);
  Serial.println();
    
  // Recursive list of all directories
  PgmPrintln("Files found in all dirs:");
  root.ls(LS_R);
  */
  Serial.println();
  PgmPrintln("Done");
    
  // Debugging complete, we start the server!
  Ethernet.begin(mac, ip, gateway);  
  server.begin();
  
  // see if the card is present and can be initialized:
  if (!SD.begin(chipSelect)) {
    Serial.println("Card failed, or not present");
    // don't do anything more:
    return;
  }
  Serial.println("card initialized.");
  
  //Prepare a clean data set. Comment to prevent this.
  SD.remove("datalog.txt");
  File dataFile = SD.open("datalog.txt", FILE_WRITE);
  dataFile.close();
  
}

// How big our line buffer should be. 100 is plenty!
#define BUFSIZ 100

void loop()
{
  //***********************************  SERVER STUFFS **********************************
  char clientline[BUFSIZ];
  char *filename;
  int index = 0;
  int image = 0;
  
  Client client = server.available();
    if (client) {
    // an http request ends with a blank line
    boolean current_line_is_blank = true;
    
    // reset the input buffer
    index = 0;
    
      while (client.connected()) {
        if (client.available()) {
          char c = client.read();
          
        // If it isn't a new line, add the character to the buffer
        if (c != '\n' && c != '\r') {
          clientline[index] = c;
          index++;
          // are we too big for the buffer? start tossing out data
          if (index >= BUFSIZ)
            index = BUFSIZ -1;
            
          // continue to read more data!
          continue;
        }
          
        // got a \n or \r new line, which means the string is done
        clientline[index] = 0;
        filename = 0;
        
        // Print it out for debugging
        Serial.println(clientline);
        
        // Look for substring such as a request to get the root file
        if (strstr(clientline, "GET / ") != 0) {
          filename = rootFileName;
        }
        if (strstr(clientline, "GET /") != 0) {
          // this time no space after the /, so a sub-file
          
          if (!filename) filename = clientline + 5; // look after the "GET /" (5 chars)
          // a little trick, look for the " HTTP/1.1" string and
          // turn the first character of the substring into a 0 to clear it out.
          (strstr(clientline, " HTTP"))[0] = 0;
          
          // print the file we want
          Serial.println(filename);
          
          if (! file.open(&root, filename, O_READ)) {
            client.println("HTTP/1.1 404 Not Found");
            client.println("Content-Type: text/html");
            client.println();
            client.println("<h2>File Not Found!</h2>");
            break;
          }
          
          Serial.println("Opened!");
          
          client.println("HTTP/1.1 200 OK");
          if (strstr(filename, ".htm") != 0)
             client.println("Content-Type: text/html");
         else if (strstr(filename, ".css") != 0)
             client.println("Content-Type: text/css");
         else if (strstr(filename, ".png") != 0)
             client.println("Content-Type: image/png");
          else if (strstr(filename, ".jpg") != 0)
             client.println("Content-Type: image/jpeg");
         else if (strstr(filename, ".gif") != 0)
             client.println("Content-Type: image/gif");
         else if (strstr(filename, ".js") != 0)
             client.println("Content-Type: application/x-javascript");
         else if (strstr(filename, ".xml") != 0)
             client.println("Content-Type: application/xml");
         else
             client.println("Content-Type: text");

          client.println();
          
          int16_t c;
          while ((c = file.read()) >= 0) {
              // uncomment the serial to debug (slow!)
              //Serial.print((char)c);
              client.print((char)c);
          }
          file.close();
        } else {
          // everything else is a 404
          client.println("HTTP/1.1 404 Not Found");
          client.println("Content-Type: text/html");
          client.println();
          client.println("<h2>File Not Found!</h2>");
           }
        break;
      }
    }
    // give the web browser time to receive the data
    delay(1);
    client.stop();
  }
  
  /**************************** DATALOGGING TEMPERATURE *********************************/
  // make a string for assembling the data to log:
  String dataString = "";
  String sensor = printDouble(Thermister(analogRead(0)),100);
  dataString += sensor;
  
  //See if it's been 30 mins, append to datalog if it has.
  unsigned long currentMillis = millis();
  
  if (currentMillis - shortMillis > 1000) {
    shortMillis = currentMillis;
    Serial.println("");
    Serial.println(analogRead(0));
    Serial.println(dataString);
  }
  
  if (currentMillis - previousMillis > interval) {
    previousMillis = currentMillis;
  
    
    // open the file.
    File dataFile = SD.open("datalog.txt", FILE_WRITE);
    
    if (dataFile.size() > 10000) {
      dataFile.close();
      SD.remove("datalog.txt");
    }      
  
    // if the file is available, write to it:
    if (dataFile) {
      dataFile.println(dataString);
      dataFile.close();
      // print to the serial port too:
      Serial.println(dataString);
    }  
    // if the file isn't open, pop up an error:
    else {
      Serial.println("error opening datalog.txt");
    } 
  }
}
