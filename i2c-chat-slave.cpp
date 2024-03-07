#include <Arduino.h>
#include <Wire.h>

String msg = "";
int mode;

void recv(int count) {
  char c = Wire.read();
  if (c == 0) {
    mode = 0;
  } else if (c == 1) {
    mode = 1;
  } else if (c == 2) {
    while (Wire.available() > 0) {
      char c = Wire.read();
      Serial.write(c);
    }
  }
}

void req() {
  if (mode == 0) {
    Wire.write(msg.length());
  } else if (mode == 1) {
    Wire.write(msg.c_str(), msg.length());
    msg = "";
  }
}

void setup() {
  Serial.begin(9600);

  Wire.begin(8);
  Wire.onReceive(recv);
  Wire.onRequest(req);
}

String input = "";

void loop() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    msg += c;
    input += c;
    if (c == '\n') {
      Serial.print("me: ");
      Serial.print(input);
      input = "";      
    }
  }
}
