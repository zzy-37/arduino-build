#include <Arduino.h>

int led_pin = 4;

void setup() {
    Serial.begin(115200);
    //pinMode(led_pin, OUTPUT);
}

void loop() {
    digitalWrite(led_pin, HIGH);
    delay(1000);
    Serial.println("hello");
    digitalWrite(led_pin, LOW);
    delay(1000);
    Serial.println("world");
}

