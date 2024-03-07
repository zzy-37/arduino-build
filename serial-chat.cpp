#include <Arduino.h>
#include <SoftwareSerial.h>

SoftwareSerial serial2(10, 11); // RX, TX
String current_msg = "";

void setup() {
  Serial.begin(9600);
  serial2.begin(4800);
}

void loop() {
  while (serial2.available() > 0) {
    char c = serial2.read();
    Serial.write(c);
  }
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\n') {
      Serial.print("me: ");
      Serial.println(current_msg);
      current_msg = " ";
    } else {
      current_msg += c;
    }
    serial2.write(c);
  }
}
