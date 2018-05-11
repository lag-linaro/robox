/*
 * Copyright (C) 2017 Lee Jones <lee.jones@linaro.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#ifndef ANBOX_SENSORS_MANAGER_H_
#define ANBOX_SENSORS_MANAGER_H_

#include "anbox/sensors/sensors_message_processor.h"
#include "anbox/sensors/sensors_sensor.h"

#include <memory>

namespace anbox {
namespace sensors {

class SensorsMessageProcessor;

class SensorsManager {
 public:
    SensorsManager();
    ~SensorsManager();

    static std::shared_ptr<SensorsManager> create();

    void set_message_processor(std::shared_ptr<SensorsMessageProcessor> processor);
    int handle_command(const std::string &command);

 private:
    std::shared_ptr<SensorsMessageProcessor> processor_;
    std::shared_ptr<sensors::Sensor> accelerometer_;
    std::shared_ptr<sensors::Sensor> magnetometer_;
    std::shared_ptr<sensors::Sensor> orientation_;
    std::shared_ptr<sensors::Sensor> proximity_;

    int list_sensors();
    int set_delay(const std::string &command);
    int toggle_on_off(const std::string &command);

    int current_;
};
}  // namespace sensors
}  // namespace anbox

#endif // ANBOX_SENSORS_MANAGER_H_
