#include <Arduino.h>

#include <Wire.h>
#include <MPU6050.h>

MPU6050 mpu;

float pitch, roll, yaw;

void setup() {
  Serial.begin(9600);  
  Wire.begin();

  mpu.initialize();

  if (!mpu.testConnection()) {
    Serial.println("MPU6050 connection failed!");
    while (1);
  }
}

void loop() {
  // Lectura aceleracion y giro
  int16_t ax, ay, az, gx, gy, gz;
  mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);

  // --- Calculo angulos ---
  roll  = atan2(ay, az) * 180 / PI;
  pitch = atan(-ax / sqrt(pow(ay, 2) + pow(az, 2))) * 180 / PI;

  static unsigned long lastTime = millis();
  unsigned long now = millis();
  float dt = (now - lastTime) / 1000.0;
  lastTime = now;
  yaw += gz / 131.0 * dt;  

  // --- Printeo serial ---
  Serial.print(pitch);
  Serial.print(",");
  Serial.print(roll);
  Serial.print(",");
  Serial.println(yaw);

  delay(50);
}
