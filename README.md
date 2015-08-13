# Patient-Generator

This repository includes a Patient Generator that will create FHIR-format json patients

This script creates geriatric patients (ages 65-85) and assigns them conditions that are more likely to occur in elderly patients. Along with conditions, the script will generate other FHIR-format resources such as corresponding medications and medication statements, relevant procedures and encounters, allergies, and observations including drinkingStatus, smokingStatus, bloodPressure, cholesterol levels, height/weight/BMI and blood glucose levels.

The script then writes each resource created (often several of each type) to a separate json file. Finally, the script sends an HTTP post request to the server for each generated resource. The script also prints the ID of each resource to the terminal along with the HTTP response code.

Notice there are two Patient_Generator files-- one is compatible with a Smart on FHIR server, the other is compatible with an intervention engine server.


# License

Copyright 2014 The MITRE Corporation

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
=======
>>>>>>> 5f6d59e4c0eea053de22ba169239a9933cf54c49
