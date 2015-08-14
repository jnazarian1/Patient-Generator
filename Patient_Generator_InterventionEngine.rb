#This script generates FHIR-format resources that, together, form synthetic geriatric patient profiles
#The script first determines the clinicali and demographic information and sets variables accordingly
#The second half of the script writes json files (one file per resource) that contain all of the information set in the variables of the first half of the script
#Finally the generated json files are uploaded to the server (in this case Intervention Engine)
#On the server, resources are linked together using references

#Working in the terminal, the script will ask the use for the url that the resources should be uploaded to
#If the url entered requires authorization, the script will ask for a valid username/email address and password
#Finally the script will ask for how many patients the user would like to generate
#There is a timeout error rescue in place that aborts the script in the case that a single patient generation takes longer than 30 seconds (it should take ~2 seconds)

#The gem 'fhir_model' is used to enable the use of FHIR formatting
#The gems 'faker' and 'random_data' are used to generate the random demographic information
#The gem 'rest-client' is used to handle the HTTP requests to the server
#Each major section of the script is seperated using two full lines of "#" for example:
#PatientGenerator#######################################################################################################################################################################################
########################################################################################################################################################################################################

require 'bundler/setup'
require 'rubygems'
require 'fhir_model'
require 'pry'
require 'faker'
require 'random_data'
require 'coderay'
require 'as-duration'
require 'net/http'
require 'uri'
require 'json'
require 'rest-client'
require 'mime-types'
require 'netrc'
require 'http-cookie'

#The following bit of code prompts the user for input regarding what server the FHIR resources should be posted to
puts "What server/url would you like to post the generated patients to?\n"
puts "The endpoints (Patient/Condition/Encounter/etc.) will be handled within the script, but an example would be \"http://localhost:3001/\"\n"
serverNameInput = gets.chomp

#The following code tests to see if authorization is required to submit an HTTP request to the server
#If the server does require authorization, it defaults to assuming that the server is a local server running on port 3001 (because that's the local IE server I was testing on)
#IMPORTANT: When it comes time to actually upload these patients to the real IE server, change 'localhost:3001' on line 39 to the url for the IE server; the authorization process should work the same
begin
  testResponse = RestClient.get "#{serverNameInput}/Patient/"
rescue
  if serverNameInput == "localhost:3001"
    puts "Authorization is required to continue.\nPlease enter a email address that is a valid username on the Intervention Engine Server:\n"
    authorizationEmail = gets.chomp
    puts "Please enter your corresponding password:\n"
    authorizationPassword = gets.chomp
    authorizationResponse = RestClient::Request.execute(method: :post, url: 'http://localhost:3001/login', payload: {"session" => {"identification" => "#{authorizationEmail}", "password" => "#{authorizationPassword}" }}.to_json)
    #If needed, my username/email address for intervention engine is "jnazarian@mitre.org" and my password is "lk" (lowercase 'LK' -- I didn't realize that password was going to stick so I made up a stupid short one on the spot)
    #The following authorization tag is used throughout the script to send resources up to the (Intervention Engine) server
    authorizationTag = authorizationResponse[22..64]
  else
    puts "An error has occured. You may need authorization to continue.\n"
  end
end

#The following code asks the user how many patients should be generated and then runs through the following 'until' loop that many times
puts "How many patients would you like to generate and post to this server?\nPlease enter a valid integer:\n"
desiredPatientCount = gets.chomp.to_i
createdPatientCounter = 0
until createdPatientCounter == desiredPatientCount
  createdPatientCounter += 1

#The following 'begin' is used for the 'rescue' at the bottom of the script that stops the script when an error occurs and opens binding.pry
begin

#The following code was used to implement a timeout error/rescue but so far it has been unecessary and has only caused problems to I am commenting it out for now
##This allows the script to continue to run if it gets stuck for some reason (I have not yet identified the reason it gets stuck)
##The script should not take more than ~5 seconds, but I set it to 30 seconds in case the server is slow
begin
#Timeout.timeout(30) do



#MockPatient#######################################################################################################################################################################################################################################################################################################
###################################################################################################################################################################################################################################################################################################################

#This method creates a FHIR-format patient resource
def createPatient(family, given)
  patient = FHIR::Patient.new(name: [FHIR::HumanName.new(family: [family], given: [given])])
end

#This decides the gender of the patient, an attribute that is used throughout the entire script
# $genderChoice is a global variable because it is used inside some loops/iterations that would not recognize it otherwise
$genderChoice = ["male","female"][rand(2)]
#The patient's name (randomly generated using the 'Faker' and 'Random' gems) is gender-dependent
if $genderChoice == "male"
  mockPatient = createPatient([Faker::Name.last_name],[Random.firstname_male])
else
  mockPatient = createPatient([Faker::Name.last_name],[Random.firstname_female])
end

#These are used at the very end of this script to fix a naming bug
mockPatientLastName = mockPatient.name[0].family
mockPatientFirstName = mockPatient.name[0].given

#This method creates a FHIR-format identifier for the patient resource
def addIdentifier(newUse, newSystem, newValue, newPeriod, newAssigner)
  newIdentifier = FHIR::Identifier.new(use: newUse, system: newSystem, value: newValue, period: {start: newPeriod}, assigner: {display: newAssigner})
end

#This code just generates a mock hospital and patient ID number
sampleHospitals = ["Mayo Clinic","Mount Sinai Hospital","UCLA Medical Center","Johns Hopkins Hospital","Mass General Hospital"]
num1 = rand(9).to_s << "."
num2 = rand(999).to_s << "."
num3 = rand(99).to_s << "."
num4 = rand(9).to_s << "."
num5 = rand(999).to_s << "."
#The following identifer codes/format may be incorrectly formatted for some hospitals as it is likely that different hospitals use different identifiers
mockPatient.identifier = [addIdentifier("usual", "urn:oid:" << num1 << num2 << num3 << num4 << "01", rand(999999).to_s, Faker::Time.between(18.months.ago, 13.months.ago), sampleHospitals[rand(5)])]

#The 'family' and 'given' names are generated above depending on the $genderChoice
#This code just assigns a random suffix if the patient is a male (because having a female, for example, be the third generation of the same name, is impossible)
mockPatient.name[0].use = "usual"
if $genderChoice == "male"
  mockPatient.name[0].suffix = [Faker::Name.suffix]
end

#This method creates a FHIR-format telecom for the patient resource
def addTelecom(newSystem, newValue, newUse)
  newTelecom = FHIR::Contact.new(system: newSystem, value: newValue, use: newUse)
end

#Randomly-selected personal contact information is generated using the 'Faker' gem
mockPatient.telecom = [addTelecom("phone",Faker::PhoneNumber.cell_phone,"home"), addTelecom("email",Faker::Internet.email,"work",)]

#This code adds a coded gender section to the patient's profile, depending on the initial gender choice
if $genderChoice == "male"
  mockPatient.gender = {"coding" => ["system" => "http://hl7.org/fhir/v3/AdministratvieGender","code" => "M", "display" => "male"],"text" => "male"}
else
  mockPatient.gender = {"coding" => ["system" => "http://hl7.org/fhir/v3/AdministrativeGender","code" => "F", "display" => "female"], "text" => "female"}
end

#This code assigns a birthdate between 65 and 85 years ago as this patient generator is tailored to geriatric patients
# 'rand(23735..31025).days' is used as opposed to 'rand(65..85).years' so the patients aren't all necessarily born on the same day of the year
mockPatient.birthDate = DateTime.now - rand(23735..31025).days

#This method creates a FHIR-format address for the patient resource
#The address includes line, city, state, zip code, and country
def addAddress(newLine, newCity, newState, newZip, newCountry)
  newAddress = FHIR::Address.new(line: newLine, city: newCity, state: newState, zip: newZip, country: newCountry)
end
#The patient's address is randomly generated by the 'Faker' gem so addresses are likely not real, but will appear realistic
#All patients generated by this generator live in the United States
mockPatient.address = [addAddress([Faker::Address.street_address], Faker::Address.city, Faker::Address.state, Faker::Address.zip, "USA")]

#This code assigns a marital status to the patient
#Although FHIR offers more coded options, this generator just decides between 'married' and 'unmarried'
maritalChance = rand(2)
if maritalChance == 1
  mockPatient.maritalStatus = {"coding" => ["system" => "http://hl7.org/fhir/v3/MaritalStatus","code" => "U","display" => "Unmarried"]}
else
  mockPatient.maritalStatus = {"coding" => ["system" => "http://hl7.org/fhir/v3/MaritalStatus","code" => "M","display" => "Married"]}
end

#This code decides that the patient was not part of a multiple birth "twins/triplets/etc."
#If for some reason, this field becomes particularly relevant, it can be randomized
mockPatient.multipleBirthBoolean = false

#This method creates a FHIR-format contact for the patient resource
#The contact information is randomized using the 'Faker' and 'Random' gems, but it assigns the contact's name to be the opposite gender of the patient (as if it is the patient's spouse)
def addContact()
  if $genderChoice == "male"
    newContact = FHIR::Patient::ContactComponent.new(name: {use: "usual", family: [Faker::Name.last_name], given: [Random.firstname_female]},                                                   telecom: [{system: "phone", value: Faker::PhoneNumber.cell_phone, use: "home"}])
  else
    newContact = FHIR::Patient::ContactComponent.new(name: {use: "usual", family: [Faker::Name.last_name], given: [Random.firstname_male]},                                                   telecom: [{system: "phone", value: Faker::PhoneNumber.cell_phone, use: "home"}])
  end
end
mockPatient.contact = [addContact()]

#This line assigns the patient a Managing Organization; it is set to MedStar for all patients as that is currently the organization sponsoring us
mockPatient.managingOrganization = {"display" => "MedStar Health"}

#This line is just to initalizes the patient 'deceased' status to false; it may change later
mockPatient.deceasedBoolean = false

#The following lines are additional fields that can be added to patients, but seemed unecessary at the time
#They can be added in the future if needed
#multipleBirthInteger
#photo
#animal
#communication
#careProvider
#link







#MockObservations#######################################################################################################################################################################################################################################################################################################
########################################################################################################################################################################################################################################################################################################################

#This method creates FHIR-format observation resources that will be linked to the patient created above
def createObservation()
  newObservation = FHIR::Observation.new()
end

#These variables pertain to Parental History, and are used to dictate the likeliness that a patient is diagnosed with a certain condition (currently only Diabetes, Hypertension, and Cancer)
#This observation may be useful for certain risk models
parent1Diabetes = [true, false, false, false, false][rand(0..4)]
parent2Diabetes = [true ,false, false, false, false][rand(0..4)]
parent1Hypertension = [true, false, false, false][rand(0..3)]
parent2Hypertension = [true, false, false, false][rand(0..3)]
parent1Cancer = [true, false, false, false][rand(0..3)]
parent2Cancer = [true, false, false, false][rand(0..3)]


#This series of code creates a 'Smoking Status' observation that uses SNOMED coding
#This observation may be useful in certain risk models
patientSmokingStatus = createObservation()
smokingChances = [1,1,2,2,2,3]
smokingChoice = smokingChances[rand(6)]
if smokingChoice == 1
  patientSmokingStatus.name = {coding: [{system: "http://snomed.info/sct", code: "77176002", display: "Smoker"}], text: "Smoking Status: Smoker"}
elsif smokingChoice == 2
  patientSmokingStatus.name = {coding: [{system: "http://snomed.info/sct", code: "266919005", display: "Never Smoked Tobacco"}], text: "Smoking Status: Never Smoked Tobacco"}
elsif smokingChoice == 3
  patientSmokingStatus.name = {coding: [{system: "http://snomed.info/sct", code: "8517006", display: "Ex-Smoker"}], text: "Smoking Status: Ex-Smoker"}
end

#This series of code creates a 'Drinking Status' observation that uses SNOMED coding
#This observation may be useful in certain risk models
patientDrinkingStatus = createObservation()
drinkingChances = [1,1,1,1,2,3]
drinkingChoice = drinkingChances[rand(6)]
if drinkingChoice == 1
  patientDrinkingStatus.name = {coding: [{system: "http://snomed.info/sct", code: "228276006", display: "Drinks Casually/Occasionally"}], text: "Drinking Status: Drinks Casually/Occasionally"}
elsif drinkingChoice == 2
  patientDrinkingStatus.name = {coding: [{system: "http://snomed.info/sct", code: "86933000", display: "Heavy Drinker"}], text: "Drinking Status: Heavy Drinker"}
elsif drinkingChoice == 3
  patientDrinkingStatus.name = {coding: [{system: "http://snomed.info/sct", code: "105543003", display: "Non-Drinker"}], text: "Drinking Status: Non-Drinker"}
end

#This series of code creates a 'Blood Pressure' observation that uses SNOMED coding
#This code picks a general class (normal/pre-hypertension/hypertension) and assigns a corresponding systolic and diastolic blood pressure
#This assignment will later dictate whether or not the patient has hypertension added as a condition as well
if parent1Hypertension == true and parent2Hypertension == true
  bpPossibilities = ["Normal","Pre-Hypertension","Pre-Hypertension","Pre-Hypertension","Hypertension","Hypertension", "Hypertension"]
else
  bpPossibilities = ["Normal","Normal","Normal","Pre-Hypertension","Pre-Hypertension","Hypertension", "Hypertension"]
end
bpChoice = bpPossibilities[rand(7)]
patientSystolicBloodPressure = createObservation()
patientSystolicBloodPressure.name = {coding: [{system: "http://snomed.info/sct", code: "271649006", display: "Systolic Blood Pressure"}], text: " Systolic Blood Pressure"}
patientSystolicBloodPressure.valueQuantity = {}
patientDiastolicBloodPressure = createObservation()
patientDiastolicBloodPressure.name = {coding: [{system: "http://snomed.info/sct", code: "271650006", display: "Diastolic Blood Pressure"}], text: "Diastolic Blood Pressure"}
patientDiastolicBloodPressure.valueQuantity = {}
case bpChoice
when "Normal"
  patientSystolicBloodPressure.valueQuantity.value = rand(100..119)
  patientDiastolicBloodPressure.valueQuantity.value = rand(65..79)
when "Pre-Hypertension"
  patientSystolicBloodPressure.valueQuantity.value = rand(120..139)
  patientDiastolicBloodPressure.valueQuantity.value = rand(80..89)
when "Hypertension"
  patientSystolicBloodPressure.valueQuantity.value = rand(140..180)
  patientDiastolicBloodPressure.valueQuantity.value = rand(90..110)
end
patientSystolicBloodPressure.valueQuantity.units = "mmHg"
patientDiastolicBloodPressure.valueQuantity.units = "mmHg"

#This series of code creates a 'Cholesterol' observation that uses SNOMED coding
#This code assigns the patient Low-Density Lipid (LDL), High-Density Lipid (HDL), and Triglyceride values
#The code is formatted this way because all three are very closely related
cholesterolChance = ["Optimal","Optimal","Optimal","Near Optimal","Borderline","Borderline","High","Very High"]
cholesterolChoice = cholesterolChance[rand(8)]
patientLDL = createObservation()
patientLDL.valueQuantity = {}
patientLDL.name = {coding: [{system: "http://snomed.info/sct", code: "314036004", display: "Plasma LDL Cholesterol Measurement"}], text: "Plasma LDL Cholesterol Measurement"}
patientHDL = createObservation()
patientHDL.valueQuantity = {}
patientHDL.name = {coding: [{system: "http://snomed.info/sct", code: "314035000", display: "Plasma HDL Cholesterol Measurement"}], text: "Plasma HDL Cholesterol Measurement"}
patientTriglyceride = createObservation()
patientTriglyceride.valueQuantity = {}
patientTriglyceride.name = {coding: [{system: "http://snomed.info/sct", code: "167082000", display: "Plasma Triglyceride Measurement"}], text: "Plasma Triglyceride Measurement"}
case cholesterolChoice
when "Optimal"
  patientLDL.valueQuantity.value = rand(80..99)
  patientHDL.valueQuantity.value = rand(60..69)
  patientTriglyceride.valueQuantity.value = rand(100..139)
when "Near Optimal"
  patientLDL.valueQuantity.value = rand(100..129)
  patientHDL.valueQuantity.value = rand(50..59)
  patientTriglyceride.valueQuantity.value = rand(140..159)
when "Borderline"
  patientLDL.valueQuantity.value = rand(130..159)
  patientHDL.valueQuantity.value = rand(40..60)
  patientTriglyceride.valueQuantity.value = rand(160..199)
when "High"
  patientLDL.valueQuantity.value = rand(160..189)
  patientHDL.valueQuantity.value = rand(40..49)
  patientTriglyceride.valueQuantity.value = rand(200..299)
when "Very High"
  patientLDL.valueQuantity.value = rand(190..220)
  patientHDL.valueQuantity.value = rand(30..39)
  patientTriglyceride.valueQuantity.value = rand(300..399)
end
#This code just assigns units to all three values
patientHDL.valueQuantity.units = "mg/dL"
patientLDL.valueQuantity.units = "mg/dL"
patientTriglyceride.valueQuantity.units = "mg/dL"

#This code creates the an 'Age' observation that will assign the patient its correct age (based on birthdate) in integer form
#This may be useful for some risk models which require age in integer format
patientAge = createObservation()
patientAge.name = {coding: [{system: "http://snomed.info/sct", code: "397669002", display: "Age"}], text: "Age"}
patientAge.valueQuantity = {}
patientAge.valueQuantity.value = Time.now.year - mockPatient.birthDate.year
patientAge.valueQuantity.units = "years"
if Time.now.month < mockPatient.birthDate.month
  patientAge.valueQuantity.value -= 1
elsif Time.now.month == mockPatient.birthDate.month
  if Time.now.day < mockPatient.birthDate.day
    patientAge.valueQuantity.value -= 1
  end
end

#This code chooses a random, relative size, and then assigns an appropriate height and weight and creates 'Height' and 'Weight' observations (coded with SNOMED)
#Essentially this code avoids super tall and super lightweight patients, as well as super short and super heavy patients
sizePossibilities = ["Small","Medium","Large","Extra Large"]
sizeChoice = sizePossibilities[rand(4)]
patientHeight = createObservation()
patientHeight.name = {coding: [{system: "http://snomed.info/sct", code: "248327008", display: "Height"}], text: "Height"}
patientHeight.valueQuantity = {}
patientWeight = createObservation()
patientWeight.name = {coding: [{system: "http://snomed.info/sct", code: "27113001", display: "Body Weight"}], text: "Weight"}
patientWeight.valueQuantity = {}
if $genderChoice == "male"
  case sizeChoice
  when "Small"
    patientHeight.valueQuantity.value = rand(60..65)
    patientWeight.valueQuantity.value = rand(100..140)
  when "Medium"
    patientHeight.valueQuantity.value = rand(65..70)
    patientWeight.valueQuantity.value = rand(140..180)
  when "Large"
    patientHeight.valueQuantity.value = rand(70..75)
    patientWeight.valueQuantity.value = rand(180..230)
  when "Extra Large"
    patientHeight.valueQuantity.value = rand(75..80)
    patientWeight.valueQuantity.value = rand(230..300)
  end
else
  case sizeChoice
  when "Small"
    patientHeight.valueQuantity.value = rand(55..60)
    patientWeight.valueQuantity.value = rand(80..120)
  when "Medium"
    patientHeight.valueQuantity.value = rand(60..65)
    patientWeight.valueQuantity.value = rand(120..160)
  when "Large"
    patientHeight.valueQuantity.value = rand(65..70)
    patientWeight.valueQuantity.value = rand(160..200)
  when "Extra Large"
    patientHeight.valueQuantity.value = rand(70..75)
    patientWeight.valueQuantity.value = rand(200..250)
  end
end
#This is just assigning labels to the previously assigned values
patientHeight.valueQuantity.units = "inches"
patientWeight.valueQuantity.units = "pounds"

#This code creates a 'Body Mass Index' observation (coded with SNOMED)
#This calculation was found on the internet, it's just the weight kg divided by the square of the height in meters
patientBMI = createObservation()
patientBMI.name = {coding: [{system: "http://snomed.info/sct", code: "60621009", display: "Body Mass Index"}], text: "Body Mass Index"}
patientBMI.valueQuantity = {}
patientWeightInKg = patientWeight.valueQuantity.value * 0.45
patientHeightInMeters = patientHeight.valueQuantity.value * 0.025
patientHeightInMetersSquared = patientHeightInMeters ** 2
patientBMI.valueQuantity.value = (patientWeightInKg/patientHeightInMetersSquared).to_i

#This code creates a 'Blood Glucose Level' observation (coded with SNOMED)
#This observation will dictate whether or not a patient has diabetes; it may also be useful for certain risk models
patientGlucose = createObservation()
patientGlucose.name = {coding: [{system: "http://snomed.info/sct", code: "33747003", display: "Blood Glucose Level"}], text: "Blood Glucose Level"}
patientGlucose.valueQuantity = {}
if parent1Diabetes == true && parent2Diabetes == true
  patientGlucose.valueQuantity.value = rand(180..250)
else
  patientGlucose.valueQuantity.value = rand(10..230)
end
patientGlucose.valueQuantity.units = "mg/dL"

#This code creates two seperate observations--'Falling History' and 'Falling Risk Test'-- both coded with SNOMED
#Falling History just tells how often (if at all) the patient Falls
#Fall Risk Test goes into a bit more detail by telling how easily the patient can bend over and pick up an object from the floor
#Both may be useful in risk model applications
#The code is formatted this way because the two are so closely related
patientFallingHistory = createObservation()
patientFallingRiskTest = createObservation()
fallingRiskVar = ["High", "Medium", "Medium", "Low", "Low", "Low", "Low"][rand(0..6)]
case fallingRiskVar
when "High"
  patientFallingHistory.name = {coding: [{system: "http://snomed.info/sct", code: "298347004", display: "Frequently"}], text: "Frequently"}
  patientFallingRiskTest.name = {coding: [{system: "http://snomed.info/sct", code: "282945009", display: "Can Not Bend to Pick Up Object Without Falling"}], text: "Can Not Bend to Pick Up Object Without Falling"}
when "Medium"
  patientFallingHistory.name = {coding: [{system: "http://snomed.info/sct", code: "298347004", display: "Falls Infrequently"}], text: "Falls Infrequently"}
  patientFallingRiskTest.name = {coding: [{system: "http://snomed.info/sct", code: "282946005", display: "Difficulty Bending to Pick Up Object Without Falling"}], text: "Can Not Bend to Pick Up Object Without Falling"}
when "Low"
  patientFallingHistory.name = {coding: [{system: "http://snomed.info/sct", code: "298345007", display: "Does Not Fall"}], text: "Does Not Fall"}
  patientFallingRiskTest.name = {coding: [{system: "http://snomed.info/sct", code: "282944008", display: "Can Bend to Pick Up Object Without Falling"}], text: "Can Not Bend to Pick Up Object Without Falling"}
end









#MockAllergies#########################################################################################################################################################################################################################################################################################################
#######################################################################################################################################################################################################################################################################################################################

#There is a 40% chance the patient is assigned an allergy and the possible allergies are limited to Mold, Bees, Latex, and Penicillin (coded with SNOMED)
allergyChances = ["N/A", "N/A", "N/A", "N/A", "N/A", "N/A", "Mold", "Bees", "Latex", "Penicillin", ]
allergyChoice = allergyChances[rand(0..9)]

#This method creates a FHIR-format allergy for the patient resource
def createAllergy()
  newAllergy = FHIR::AllergyIntolerance.new(status: "generated")
end
unless allergyChoice == "N/A"
  allergyName = "Allergy to " << allergyChoice
  mockAllergy = createAllergy()
  if allergyChoice == "Mold"
    allergyCode = "419474003"
  elsif allergyChoice == "Bees"
    allergyCode = "424213003"
  elsif allergyChoice == "Latex"
    allergyCode = "300916003"
  elsif allergyChoice == "Penicillin"
    allergyCode = "91936005"
  else
    return "Error: Incorrect allergyChoice"
  end
  mockAllergy.identifier[0] = {"label" => "#{allergyName}", "system" => "http://snomed.info/sct", "value" => "#{allergyCode}"}
  mockAllergy.criticality = ["low","high"][rand(0..1)]
  mockAllergy.status = "confirmed"
  mockAllergy.substance = {"display" => "#{allergyName}"}
end








#MockConditions#########################################################################################################################################################################################################################################################################################################
########################################################################################################################################################################################################################################################################################################################

#These are just empty arrays that will keep track of the patients conditions/medications/encounters/medicationStatements/procedures
#Every time the script goes through the following 'until' loop, the information is added to these three arrays
$allConditions = []
allMedications = []
allMedicationStatements = []
allEncounters = []
allProcedures = []
pastConditionIndices = []

#This loop will give the patients one condition, the corresponding medication (if applicable), and all appropriate encounters and procedures for each iteration
#The number of iterations through this loop (essentially the number of conditions) is randomized for each patient
#The code is formatted this way so it is most likely that patients have 2-3 conditions as that is more realistic
conditionCounter = 0
numberOfConditionPossibilities = [0,1,1,2,2,2,2,3,3,3,3,3,3,4,4,4,5,5,6,7]
numberOfConditions = numberOfConditionPossibilities[rand(numberOfConditionPossibilities.count)-1]

#This line just initializes variables outside of the condition-creating loop that follows
postOperativeVar = false
hadColonoscopy = false
hadMammography = false

#This 'if' statement ensures that if the patient has high blood pressure, then the patient MUST have at least 1 condition (and it will be hypertension)
if bpChoice == "Hypertension"
  if numberOfConditions == 0
    numberOfConditions = numberOfConditions + 1
  end
end
#This 'if' statement ensures that if the patient has high glucose levels, then the patient MUST have at least 1 condition (and it will be diabetes)
if patientGlucose.valueQuantity.value > 200
  if numberOfConditions == 0
    numberOfConditions = numberOfConditions + 1
  #This 'elsif' statement ensures that if the patient has high blood pressure AND high glucose levels, then the patient MUST have at least 2 conditions (and they will be hypertension and diabetes)
  elsif numberOfConditions == 1
    if bpChoice == "Hypertension"
      numberOfConditions = numberOfConditions + 1
    end
  end
end

#This just specifies that the patient has not died if he/she does not have any conditions (because death is otherwise specified in the condition loop)
if conditionCounter == 0
  mockPatient.deceasedBoolean == false
end

#This is the beginning of a rather lengthy loop
#Each iteration creates one condition, one medication/medication statement duo (if applicable), and all encounters and procedures related to the condition assigned
until conditionCounter == numberOfConditions
  conditionCounter = conditionCounter + 1

#This method creates a FHIR-format condition for the patient resource
def createCondition()
  newCondition = FHIR::Condition.new(status: "generated")
end

#This is an array of hashes, each hash being a possible condition
#An index is then chosen randomly, therefore randomizing the conditions given to each patient
#If medication_id == 0, then there is no medication (nor a medication statement) for that condition
#mortalityChance is a value out of 100 representing the chance of dying from that disease after being diagnosed-- 0 means it is non fatal, 100 means there is no cure and it will cause sure death
#The healOrDeath field identifies conditions that are either cured in a timely manner or cause death (such as intracranial hemmhoraging) when it is not likely/possible for the disease to just linger for a long period of time
conditionRepository = [
  {condition_id: 1, icd9code: "401.9",   display: "Hypertension",                           medication_id: 8,  overnights: "0",     abatementChance: 40,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},                                                  #You can't die from hypertension, you die fromthe conditions hypertension causes
  {condition_id: 2, icd9code: "250.00",  display: "Diabetes",                               medication_id: 4,  overnights: "1-2",   abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},                                                  #Couldn't find a death rate above like .01% anywhere but I can keep looking, also I know Diabetes can cause other conditions that may need surgery, but surgery is not done to cure diabetes
  {condition_id: 3, icd9code: "290.0",   display: "Dementia",                               medication_id: 1,  overnights: "0",     abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},                                                  #Dementia can cause other conditions that may need surgery, but surgery is not done to cure dementia
  {condition_id: 4, icd9code: "482.9",   display: "Bacterial Pneumonia",                    medication_id: 2,  overnights: "4-6",   abatementChance: 100, healOrDeath: true,  mortalityChance: 12, mortalityTime: "threeWeeks",   recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "weekLater",               procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 5, icd9code: "428.0",   display: "Congestive Heart Failure",               medication_id: 3,  overnights: "5-7",   abatementChance: 20,  healOrDeath: false, mortalityChance: 40, mortalityTime: "fourYears",    recoveryEstimate: "sixMonths",   procedureChance: 80, procedureSuccess: 60, checkUp: "weekLater",               procedureDescription: "Surgery to remove blockages from cardiovascular arteries and/or valves",                          procedureCode: "34051", procedureCodeName: "Arterial Embolectomy"},
  {condition_id: 6, icd9code: "365.72",  display: "Glaucoma",                               medication_id: 5,  overnights: "0",     abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 80, procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "Laser eye surgery to reduce intraocular pressure",                                                procedureCode: "66761", procedureCodeName: "Iridotomy/Iridectomy by Laser Surgery"},
  {condition_id: 7, icd9code: "711.90",  display: "Arthritis",                              medication_id: 6,  overnights: "0",     abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 8, icd9code: "487.8",   display: "Influenza",                              medication_id: 7,  overnights: "3-4",   abatementChance: 100, healOrDeath: true,  mortalityChance: 5,  mortalityTime: "threeWeeks",   recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 9, icd9code: "733.01",  display: "Osteoporosis",                           medication_id: 9,  overnights: "0",     abatementChance: 0,   healOrDeath: false, mortalityChance: 5,  mortalityTime: "sevenYears",   recoveryEstimate: "N/A",         procedureChance: 20, procedureSuccess: 0,  checkUp: "ifProcedure-CastRemoval", procedureDescription: "Surgery to resest hip fracture",                                                                  procedureCode: "27220", procedureCodeName: "Closed treatment of Acetabulum (Hip Socket) Fracture"},
  {condition_id: 10, icd9code: "466.0",  display: "Chronic Bronchitis",                     medication_id: 18, overnights: "4-6",   abatementChance: 40,  healOrDeath: false, mortalityChance: 40, mortalityTime: "fourYears",    recoveryEstimate: "week",        procedureChance: 10, procedureSuccess: 20, checkUp: "none",                    procedureDescription: "Surgery to remove damaged lung tissue",                                                           procedureCode: "32480", procedureCodeName: "Lobectomy, Partial Removal of Lung"},
  {condition_id: 11, icd9code: "389.9",  display: "Hearing Loss",                           medication_id: 0,  overnights: "0",     abatementChance: 75,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "threeMonths", procedureChance: 20, procedureSuccess: 80, checkUp: "none",                    procedureDescription: "Surgery to remove blockages obstructing ear canal",                                               procedureCode: "69200", procedureCodeName: "Reomval of foreign body from external auditory canal"},
  {condition_id: 12, icd9code: "535.00", display: "Gastritis",                              medication_id: 12, overnights: "3-4",   abatementChance: 70,  healOrDeath: false, mortalityChance: 3,  mortalityTime: "twoYears",     recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},                                                  #Double check if surgery can actually be helpful
  {condition_id: 13, icd9code: "244.9",  display: "Hypothyroidism",                         medication_id: 13, overnights: "0",     abatementChance: 40,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 5,  procedureSuccess: 30, checkUp: "ifProcedure-weekLater",   procedureDescription: "Surgery to remove parts or all of the thyroid",                                                   procedureCode: "60252", procedureCodeName: "Partial Thyroidectomy"},                                #You can't die from Hypothyroidism, you can die from the complicaitons it causes
  {condition_id: 14, icd9code: "285.9",  display: "Anemia",                                 medication_id: 14, overnights: "4-5",   abatementChance: 80,  healOrDeath: false, mortalityChance: 5,  mortalityTime: "twoYears",     recoveryEstimate: "sixMonths",   procedureChance: 25, procedureSuccess: 80, checkUp: "none",                    procedureDescription: "Blood transfusion and stem cell transplant",                                                      procedureCode: "36430", procedureCodeName: "Blood Transfusion"},
  {condition_id: 15, icd9code: "492.8",  display: "Emphysema",                              medication_id: 15, overnights: "3-5",   abatementChance: 0,   healOrDeath: false, mortalityChance: 30, mortalityTime: "fourYears",    recoveryEstimate: "N/A",         procedureChance: 20, procedureSuccess: 0,  checkUp: "ifProcedure-weekLater",   procedureDescription: "Lung volume reduction surgery",                                                                   procedureCode: "32491", procedureCodeName: "Lung Volume Reduction"},
  {condition_id: 16, icd9code: "533.30", display: "Peptic Ulcer",                           medication_id: 16, overnights: "6-7",   abatementChance: 80,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "threeMonths", procedureChance: 5,  procedureSuccess: 50, checkUp: "ifProcedure-weekLater",   procedureDescription: "Widening/removing part of the stomach",                                                           procedureCode: "43631", procedureCodeName: "Partial Gastrectomy"},
  {condition_id: 17, icd9code: "554.1",  display: "Varicose Veins",                         medication_id: 17, overnights: "5-7",   abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 18, icd9code: "362.50", display: "Macular Degeneration",                   medication_id: 10, overnights: "0",     abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 5,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "Implanted miniature telescope in the patient's eye",                                              procedureCode: "66985", procedureCodeName: "Insertion of Intraocular Lens Prothesis"},
  {condition_id: 19, icd9code: "274.9",  display: "Gout",                                   medication_id: 19, overnights: "4-6",   abatementChance: 90,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 5,  procedureSuccess: 80, checkUp: "none",                    procedureDescription: "Ankle replacement and uric acid crystal removal",                                                 procedureCode: "27702", procedureCodeName: "Ankle Replacement"},
  {condition_id: 20, icd9code: "564.00", display: "Constipation",                           medication_id: 20, overnights: "0",     abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 21, icd9code: "440.9",  display: "Athersclerosis",                         medication_id: 8,  overnights: "3-5",   abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 25, procedureSuccess: 0,  checkUp: "ifProcedure-weekLater",   procedureDescription: "Surgery to remove plaque from arterial walls",                                                    procedureCode: "33572", procedureCodeName: "Coronary Endarterectomy"},
  {condition_id: 22, icd9code: "416.9",  display: "Pulmonary Heart Disease",                medication_id: 8,  overnights: "5-7",   abatementChance: 30,  healOrDeath: false, mortalityChance: 15, mortalityTime: "twoYears",     recoveryEstimate: "sixMonths",   procedureChance: 15, procedureSuccess: 30, checkUp: "ifProcedure-weekLater",   procedureDescription: "Pulmonary Artery Embolectomy (Surgery to remove blockages and/or clots in the pulmonary system)", procedureCode: "33910", procedureCodeName: "Pulmonary Artery Embolectomy"},
  {condition_id: 23, icd9code: "530.81", display: "Esophageal Reflux",                      medication_id: 16, overnights: "0",     abatementChance: 70,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "threeMonths", procedureChance: 30, procedureSuccess: 90, checkUp: "ifProcedure-weekLater",   procedureDescription: "Laparoscopic surgery to reinforce the passage between the esophagus and the stomach",             procedureCode: "31760", procedureCodeName: "Intrathoracic Tracheoplasty"},
  {condition_id: 24, icd9code: "003.9",  display: "Salmonella",                             medication_id: 21, overnights: "3-5",   abatementChance: 100, healOrDeath: true,  mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 25, icd9code: "011.90", display: "Pulmonary Tuberculosis",                 medication_id: 22, overnights: "15-20", abatementChance: 80,  healOrDeath: false, mortalityChance: 20, mortalityTime: "threeWeeks",   recoveryEstimate: "sixMonths",   procedureChance: 10, procedureSuccess: 30, checkUp: "ifProcedure-weekLater",   procedureDescription: "Surgery to remove pocket(s) of bacteria and repair lung damage",                                  procedureCode: "32140", procedureCodeName: "Thoracotomy to remove bacteria-filled cyst"},
  {condition_id: 26, icd9code: "265.0",  display: "Beriberi",                               medication_id: 23, overnights: "0",     abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "threeMonths", procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 27, icd9code: "377.75", display: "Cortical Blindness",                     medication_id: 0,  overnights: "1-3",   abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 28, icd9code: "733.20", display: "Bone Cyst",                              medication_id: 0,  overnights: "4-6",   abatementChance: 90,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 10, procedureSuccess: 90, checkUp: "ifProcedure-weekLater",   procedureDescription: "Drained cyst and filled hole with bone chips from other locations tihin the patient",             procedureCode: "20615", procedureCodeName: "Aspiration Treatment of Bone Cyst"},
  {condition_id: 29, icd9code: "814.00", display: "Carpal Bone Fracture",                   medication_id: 0,  overnights: "0-1",   abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "threeMonths", procedureChance: 40, procedureSuccess: 90, checkUp: "ifProcedure-CastRemoval", procedureDescription: "Reset fractured hand bone",                                                                       procedureCode: "26605", procedureCodeName: "Reset Hand Fracture"},
  {condition_id: 30, icd9code: "825.20", display: "Foot Fracture",                          medication_id: 0,  overnights: "0-1",   abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "threeMonths", procedureChance: 40, procedureSuccess: 90, checkUp: "ifProcedure-CastRemoval", procedureDescription: "Reset fractured foot bone",                                                                       procedureCode: "28435", procedureCodeName: "Reset Foot Fracture"},
  {condition_id: 31, icd9code: "541",    display: "Appendicitis",                           medication_id: 0,  overnights: "3-4",   abatementChance: 100, healOrDeath: true,  mortalityChance: 3,  mortalityTime: "threeWeeks",   recoveryEstimate: "week",        procedureChance: 95, procedureSuccess: 90, checkUp: "ifProcedure-weekLater",   procedureDescription: "Appendectomy",                                                                                    procedureCode: "44950", procedureCodeName: "Appendectomy"},
  {condition_id: 32, icd9code: "943.01", display: "Forearm Burn",                           medication_id: 0,  overnights: "0-2",   abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 33, icd9code: "945.06", display: "Thigh Burn",                             medication_id: 0,  overnights: "2-4",   abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 34, icd9code: "004.2",  display: "Shigella",                               medication_id: 0,  overnights: "4-5",   abatementChance: 90,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 35, icd9code: "023.9",  display: "Brucellosis",                            medication_id: 24, overnights: "10-15", abatementChance: 100, healOrDeath: true,  mortalityChance: 2,  mortalityTime: "threeWeeks",   recoveryEstimate: "sixMonths",   procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 36, icd9code: "033.0",  display: "Whooping Cough (B. Pertussis)",          medication_id: 25, overnights: "3-4",   abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 37, icd9code: "081.9",  display: "Typhus",                                 medication_id: 2,  overnights: "3-9",   abatementChance: 100, healOrDeath: true,  mortalityChance: 30, mortalityTime: "threeWeeks",   recoveryEstimate: "threeMonths", procedureChance: 0,  procedureSuccess: 0,  checkUp: "weekLater",               procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 38, icd9code: "072.9",  display: "Mumps",                                  medication_id: 0,  overnights: "3-5",   abatementChance: 95,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 39, icd9code: "272.4",  display: "Hyperlipidemia",                         medication_id: 11, overnights: "0",     abatementChance: 70,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 20, procedureSuccess: 95, checkUp: "ifProcedure-weekLater",   procedureDescription: "Gastric Bypass Surgery",                                                                          procedureCode: "43847", procedureCodeName: "Gastric Bypass"},
  {condition_id: 40, icd9code: "781.1",  display: "Disturbances of Smell and Taste",        medication_id: 11, overnights: "0",     abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 60, procedureSuccess: 75, checkUp: "none",                    procedureDescription: "Surgery to restore sensory pathways involving smell and taste",                                   procedureCode: "97533", procedureCodeName: "Sensory Integrative Techniques"},
  {condition_id: 41, icd9code: "162.9",  display: "Lung Cancer",                            medication_id: 29, overnights: "5-7",   abatementChance: 15,  healOrDeath: false, mortalityChance: 70, mortalityTime: "twoYears",     recoveryEstimate: "threeYears",  procedureChance: 40, procedureSuccess: 20, checkUp: "chemotherapy",            procedureDescription: "Surgery to remove tumors in the thoracic cavity",                                                 procedureCode: "32503", procedureCodeName: "Lung Tumor Removal"},
  {condition_id: 42, icd9code: "153.9",  display: "Colon Cancer",                           medication_id: 30, overnights: "8-10",  abatementChance: 70,  healOrDeath: false, mortalityChance: 50, mortalityTime: "twoyears",     recoveryEstimate: "threeYears",  procedureChance: 70, procedureSuccess: 60, checkUp: "chemotherapy",            procedureDescription: "Colectomy (Surgery to remove a cancerous portion of the colon)",                                  procedureCode: "44140", procedureCodeName: "Partial Colectomy with Anastomosis"},
  {condition_id: 43, icd9code: "172.9",  display: "Skin Cancer (Melanoma)",                 medication_id: 31, overnights: "4-6",   abatementChance: 95,  healOrDeath: false, mortalityChance: 20, mortalityTime: "twoYears",     recoveryEstimate: "threeYears",  procedureChance: 75, procedureSuccess: 98, checkUp: "none",                    procedureDescription: "Mohs surgery (a form of skin grafting to replace cancerous skin cells)",                          procedureCode: "17311", procedureCodeName: "Mohs Micrographic Technique"},
  {condition_id: 44, icd9code: "585.3",  display: "Chronic Kidney Disease",                 medication_id: 0,  overnights: "3-5",   abatementChance: 0,   healOrDeath: false, mortalityChance: 20, mortalityTime: "sevenYears",   recoveryEstimate: "N/A",         procedureChance: 10, procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "Kidney Transplant",                                                                               procedureCode: "50360", procedureCodeName: "Kidney Transplant"},
  {condition_id: 45, icd9code: "155.2",  display: "Liver Cancer",                           medication_id: 32, overnights: "6-8",   abatementChance: 25,  healOrDeath: false, mortalityChance: 85, mortalityTime: "fourYears",    recoveryEstimate: "threeYears",  procedureChance: 25, procedureSuccess: 40, checkUp: "chemotherapy",            procedureDescription: "Hepatectomy (Surgery to remove a cancerous portion of the liver)",                                procedureCode: "47120", procedureCodeName: "Partial Hepatectomy"},
  {condition_id: 46, icd9code: "478.9",  display: "Upper Respiratory Tract Disease",        medication_id: 15, overnights: "0-1",   abatementChance: 90,  healOrDeath: false, mortalityChance: 2,  mortalityTime: "threeWeeks",   recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 47, icd9code: "571.5",  display: "Cirrhosis of Liver",                     medication_id: 33, overnights: "3-5",   abatementChance: 0,   healOrDeath: false, mortalityChance: 40, mortalityTime: "twoYears",     recoveryEstimate: "N/A",         procedureChance: 20, procedureSuccess: 50, checkUp: "ifProcedure-weekLater",   procedureDescription: "Liver transplant",                                                                                procedureCode: "47136", procedureCodeName: "Liver Transplant"},
  {condition_id: 48, icd9code: "117.3",  display: "Aspergillosis",                          medication_id: 34, overnights: "20-30", abatementChance: 50,  healOrDeath: false, mortalityChance: 60, mortalityTime: "twoYears",     recoveryEstimate: "threeYears",  procedureChance: 10, procedureSuccess: 40, checkUp: "ifProcedure-weekLater",   procedureDescription: "Thoracentesis (Surgery to drain and/or remove lung mass)",                                        procedureCode: "32554", procedureCodeName: "Thoracentesis"},
  {condition_id: 49, icd9code: "136.0",  display: "Ainhum",                                 medication_id: 0,  overnights: "0",     abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 60, procedureSuccess: 30, checkUp: "none",                    procedureDescription: "Toe amputation",                                                                                  procedureCode: "28820", procedureCodeName: "Toe Amputation"},
  {condition_id: 50, icd9code: "266.0",  display: "Ariboflavinosis",                        medication_id: 0,  overnights: "0",     abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "threeMonths", procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 51, icd9code: "276.2",  display: "Acidosis",                               medication_id: 35, overnights: "0-1",   abatementChance: 90,  healOrDeath: false, mortalityChance: 5,  mortalityTime: "twoYears",     recoveryEstimate: "threeYears",  procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 52, icd9code: "041.00", display: "Streptococcus",                          medication_id: 36, overnights: "0-1",   abatementChance: 100, healOrDeath: true,  mortalityChance: 5,  mortalityTime: "threeWeeks",   recoveryEstimate: "week",        procedureChance: 25, procedureSuccess: 90, checkUp: "ifProcedure-weekLater",   procedureDescription: "Tonsilectomy to prevent future Strep Throat",                                                     procedureCode: "42842", procedureCodeName: "Tonsilectomy"},
  {condition_id: 53, icd9code: "696.1",  display: "Psoriasis",                              medication_id: 37, overnights: "0",     abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 54, icd9code: "204.90", display: "Lymphatic Leukemia",                     medication_id: 38, overnights: "20-35", abatementChance: 20,  healOrDeath: false, mortalityChance: 75, mortalityTime: "fourYears",    recoveryEstimate: "threeYears",  procedureChance: 0,  procedureSuccess: 0,  checkUp: "chemotherapy",            procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 55, icd9code: "279.06", display: "Common Variable Immunodeficieny",        medication_id: 0,  overnights: "3-5",   abatementChance: 5,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 30, procedureSuccess: 75, checkUp: "ifProcedure-weekLater",   procedureDescription: "Bone Marrow/Stem Cell Transplant",                                                                procedureCode: "38241", procedureCodeName: "Hematopoietic Progenitor Cell Transplantation"},
  {condition_id: 56, icd9code: "324.1",  display: "Intraspinal Abscess",                    medication_id: 0,  overnights: "0",     abatementChance: 85,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 60, procedureSuccess: 95, checkUp: "weekLater",               procedureDescription: "Surgery to Remove Intraspinal Abscess",                                                           procedureCode: "20005", procedureCodeName: "Soft Tissue Drainage/Removal"},
  {condition_id: 57, icd9code: "324.0",  display: "Intracranial Abscess",                   medication_id: 0,  overnights: "0",     abatementChance: 85,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 60, procedureSuccess: 95, checkUp: "weekLater",               procedureDescription: "Surgery to Remove Intracranial Abscess",                                                          procedureCode: "20005", procedureCodeName: "Soft Tissue Drainage/Removal"},
  {condition_id: 58, icd9code: "780.52", display: "Insomnia",                               medication_id: 39, overnights: "0",     abatementChance: 35,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 59, icd9code: "346.70", display: "Chronic Migraines",                      medication_id: 40, overnights: "0",     abatementChance: 35,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 60, icd9code: "345.90", display: "Epilepsy",                               medication_id: 41, overnights: "0",     abatementChance: 0,   healOrDeath: false, mortalityChance: 30, mortalityTime: "threeYears",   recoveryEstimate: "N/A",         procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 61, icd9code: "360.60", display: "Foreign Body in Eye",                    medication_id: 0,  overnights: "0",     abatementChance: 95,  healOrDeath: false, mortalityChance: 2,  mortalityTime: "threeWeeks",   recoveryEstimate: "week",        procedureChance: 95, procedureSuccess: 95, checkUp: "none",                    procedureDescription: "Surgery to Remove Embedded Foreign Body in Eye",                                                  procedureCode: "65210", procedureCodeName: "Removal of Foreign Body from External Eye"},
  {condition_id: 62, icd9code: "E819.0", display: "Injuries from a Motor Vehicle Accident", medication_id: 0,  overnights: "0-2",   abatementChance: 100, healOrDeath: true,  mortalityChance: 10, mortalityTime: "day",          recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "ifProcedure-weekLater",   procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 63, icd9code: "E880.9", display: "Injuries from a Fall on Stairs",         medication_id: 0,  overnights: "0-2",   abatementChance: 100, healOrDeath: true,  mortalityChance: 5,  mortalityTime: "day",          recoveryEstimate: "week",        procedureChance: 60, procedureSuccess: 90, checkUp: "ifProcedure-weekLater",   procedureDescription: "Surgery to resest hip fracture",                                                                  procedureCode: "27220", procedureCodeName: "Closed treatment of Acetabulum (Hip Socket) Fracture"},
  {condition_id: 64, icd9code: "523.01", display: "Gingivitis",                             medication_id: 42, overnights: "0",     abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 65, icd9code: "692.70", display: "Dermatitis due to Sun Exposure",         medication_id: 15, overnights: "0",     abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 66, icd9code: "737.30", display: "Scoliosis Idiopathic",                   medication_id: 0,  overnights: "2-5",   abatementChance: 0,   healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 50, procedureSuccess: 0,  checkUp: "ifProcedure-weekLater",   procedureDescription: "Surgery to Correct Spine Curvature",                                                              procedureCode: "22802", procedureCodeName: "Posterior Arthrodesis"},
  {condition_id: 67, icd9code: "788.30", display: "Urinary Incontinence",                   medication_id: 0,  overnights: "0",     abatementChance: 30,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "sixMonths",   procedureChance: 25, procedureSuccess: 70, checkUp: "weekLater",               procedureDescription: "Insertion of Inflatable Urethral/Bladder Neck Sphincter",                                         procedureCode: "53445", procedureCodeName: "Insertion of Inflatable Urethral/Bladder Neck Sphincter"},
  {condition_id: 68, icd9code: "432.9",  display: "Intracranial Hemorrhaging",              medication_id: 0,  overnights: "3-10",  abatementChance: 25,  healOrDeath: true,  mortalityChance: 75, mortalityTime: "day",          recoveryEstimate: "sixMonths",   procedureChance: 95, procedureSuccess: 25, checkUp: "weekLater",               procedureDescription: "Craniectomy to Remove Hematoma",                                                                  procedureCode: "61312", procedureCodeName: "Craniectomy to Remove Hematoma"},
  {condition_id: 69, icd9code: "388.70", display: "Otalgia (Earache)",                      medication_id: 43, overnights: "0",     abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 70, icd9code: "537.3",  display: "Obstruction of Duodenum",                medication_id: 0,  overnights: "4-6",   abatementChance: 100, healOrDeath: true,  mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 90, procedureSuccess: 95, checkUp: "none",                    procedureDescription: "Surgery to remove Intestinal Blockage",                                                           procedureCode: "44615", procedureCodeName: "Intestinal Stricturoplasty"},
  {condition_id: 71, icd9code: "550.90", display: "Inguinal Hernia",                        medication_id: 0,  overnights: "1-2",   abatementChance: 90,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 95, procedureSuccess: 90, checkUp: "weekLater",               procedureDescription: "Laparoscopic Surgery to Repair Inguinal Hernia",                                                  procedureCode: "49650", procedureCodeName: "Laparoscopic Surgery to Repair Inguinal Hernia"},
  {condition_id: 72, icd9code: "873.63", display: "Broken Tooth",                           medication_id: 0,  overnights: "0-1",   abatementChance: 100, healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 20, procedureSuccess: 85, checkUp: "none",                    procedureDescription: "Root canal",                                                                                      procedureCode: "41899", procedureCodeName: "Root Canal"},
  {condition_id: 73, icd9code: "787.20", display: "Dysphagia (Trouble Swallowing)",         medication_id: 0,  overnights: "0-1",   abatementChance: 50,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "threeMonths", procedureChance: 35, procedureSuccess: 95, checkUp: "ifProcedure-weekLater",   procedureDescription: "Gastrostomy (Feeding Tube)",                                                                      procedureCode: "43830", procedureCodeName: "Gastrostomy (Feeding Tube)"},
  {condition_id: 74, icd9code: "599.0",  display: "Urinary Tract Infection",                medication_id: 44, overnights: "2-4",   abatementChance: 90,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "week",        procedureChance: 0,  procedureSuccess: 0,  checkUp: "weekLater",               procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 75, icd9code: "434.90", display: "Stroke without Cerebral Infarction",     medication_id: 45, overnights: "4-7",   abatementChance: 75,  healOrDeath: false, mortalityChance: 40, mortalityTime: "day",          recoveryEstimate: "sixMonths",   procedureChance: 75, procedureSuccess: 10, checkUp: "weekLater",               procedureDescription: "Cerebral Thrombolysis by Intervention Fusion",                                                    procedureCode: "37195", procedureCodeName: "Cerebral Thrombolysis by Intervention Fusion"},
  {condition_id: 76, icd9code: "434.91", display: "Stroke with Cerebral Infarction",        medication_id: 45, overnights: "5-8",   abatementChance: 75,  healOrDeath: false, mortalityChance: 60, mortalityTime: "day",          recoveryEstimate: "threeYears",  procedureChance: 95, procedureSuccess: 5,  checkUp: "weekLater",               procedureDescription: "Cerebral Thrombolysis by Intervention Fusion",                                                    procedureCode: "37195", procedureCodeName: "Cerebral Thrombolysis by Intervention Fusion"},
  {condition_id: 77, icd9code: "296.30", display: "Major Depressive Disorder",              medication_id: 46, overnights: "0",     abatementChance: 60,  healOrDeath: false, mortalityChance: 0,  mortalityTime: "N/A",          recoveryEstimate: "N/A",         procedureChance: 0,  procedureSuccess: 0,  checkUp: "none",                    procedureDescription: "N/A",                                                                                             procedureCode: "00000", procedureCodeName: "N/A"},
  {condition_id: 78, icd9code: "571.2",  display: "Alcoholic Cirrhosis of Liver",           medication_id: 33, overnights: "5-7",   abatementChance: 0,   healOrDeath: false, mortalityChance: 40, mortalityTime: "twoYears",     recoveryEstimate: "N/A",         procedureChance: 10, procedureSuccess: 50, checkUp: "ifProcedure-weekLater",   procedureDescription: "Liver transplant",                                                                                procedureCode: "47136", procedureCodeName: "Liver Transplant"},
  {condition_id: 79, icd9code: "185",    display: "Prostate Cancer",                        medication_id: 27, overnights: "2-4",   abatementChance: 90,  healOrDeath: false, mortalityChance: 19, mortalityTime: "twoYears",     recoveryEstimate: "threeYears",  procedureChance: 75, procedureSuccess: 98, checkUp: "chemotherapy",            procedureDescription: "Radical Prostatectomy",                                                                           procedureCode: "55810", procedureCodeName: "Radical Prostatectomy"},
  {condition_id: 80, icd9code: "174.9",  display: "Breast Cancer",                          medication_id: 28, overnights: "2-3",   abatementChance: 40,  healOrDeath: false, mortalityChance: 24, mortalityTime: "twoYears",     recoveryEstimate: "threeYears",  procedureChance: 60, procedureSuccess: 60, checkUp: "chemotherapy",            procedureDescription: "Mastectomy (Surgery to remove part or all of a cancerous breast)",                                procedureCode: "19301", procedureCodeName: "Partial Mastectomy"},
  {condition_id: 81, icd9code: "998.59", display: "Post-Operative Infection",               medication_id: 18, overnights: "0-2",   abatementChance: 100, healOrDeath: true,  mortalityChance: 5,  mortalityTime: "threeWeeks",   recoveryEstimate: "week",        procedureChance: 5,  procedureSuccess: 95, checkUp: "weekLater",               procedureDescription: "Incision and Drainage of Postoperative Wound Infection",                                          procedureCode: "10180", procedureCodeName: "Incision and Drainage of Postoperative Wound Infection"}
    ]

#This code creates a condition then chooses a random index that dictates which condition in the repository is assigned
mockCondition = createCondition()
mockCondition.subject = {reference: "mockPatient/",
                         display: mockPatient.name[0].given.to_s[3...mockPatient.name[0].given.to_s.length-3] << " " << mockPatient.name[0].family.to_s[3...mockPatient.name[0].family.to_s.length-3]}

#This 'if/else' makes it so the patients are more likely to have the top ten most common geriatric diseases (but it is still possible for them to have any condition in the conditionRepository)
#The first ten conditions in the repositiory are the top ten most likely conditions diagnosed in geriatric patients, so this creates a 1 in 3 chance that the condition assigned is a top-ten geriatic condition
conditionChoice = rand(3)
if conditionChoice == 1
  conditionIndex = rand(0..9)
else
  conditionIndex = rand(conditionRepository.count-1) - 1
end

#This 'if' statement makes emphysema and lung cancer and respiratory tract disease more likely if the patient is a smoker
if smokingChoice == 2
  emphysemaChance = rand(5)
  if emphysemaChance == 4
    conditionIndex = 14
  end
end

#This 'if' statement creates a 1 in 3 chance that patients with Emphysema will also have Lung Cancer
if $allConditions.include? ("Emphysema")
  lungCancerChance = rand(3)
  if lungCancerChance == 2
    conditionIndex = 40
  end
end

#This 'if' statement creates a 1 in 4 chance that patients with Emphysema will also have Upper Respiratory Tract Disease
if $allConditions.include? ("Emphysema")
  unless conditionIndex == 40
    respiratoryDiseaseChance = rand(4)
    if respiratoryDiseaseChance == 3
      conditionIndex = 45
    end
  end
end

#This 'if' statement creates a 1 in 4 chance that patients with Emphysema will also have Bronchitis (unless they also have Lung Cancer or Respiratory Tract Disease)
if $allConditions.include? ("Emphysema")
  unless conditionIndex == 40 || 45 #These condition indexes are Lung Cancer and Upper Respiratory Tract Disease
    bronchitisChance = rand(4)
    if bronchitisChance == 3
      conditionIndex = 9
    end
  end
end

#This 'if' statement makes liver disease more likely if the patients are heavy drinkers (decided in observations)
if patientDrinkingStatus == 2
  unless conditionIndex == 14 || 40 || 45 || 9 #These condition indexes are not to be overwritten- Emphysema/LungCancer/UpperRespiratoryTractDisease/Bronchitis
    liverDiseaseChance = rand(4)
    if liverDiseaseChance == 3
      conditionIndex = 46 #This is the condition index for Cirrhosis of Liver
    elsif liverDiseaseChance == 2
      conditionIndex = 77 #This is the condition index for Alcoholic Cirrhosis of Liver
    end
  end
end

#This 'if/else' statement ensures that patients have the Alcohlic Cirrhosis condition if and only if they are heavy drinkers (decided in observations)
unless patientDrinkingStatus == 2
  while conditionRepository[conditionIndex][:display] == "Alcoholic Cirrhosis of Liver"
    conditionIndex = 46
  end
end
if patientDrinkingStatus == 2
  if conditionRepository[conditionIndex][:display] == "Cirrhosis of Liver"
    conditionIndex = 77
  end
end

#This 'if/else' statement makes heart disease more common if the patients have hypertension
if bpChoice == "Hypertension"
  heartDiseaseChance = rand(5)
  if heartDiseaseChance == 2
    conditionIndex = 4 #This condition index leads to Congestive Heart Failure
  elsif heartDiseaseChance == 3
    conditionIndex = 21 #This condition index leads to Pulmonary Heart Disease
  end
end

#These 'if/else' statements ensures that only men can have prostate cancer and only women can have breast cancer (because it is super unlikely for men)
if $genderChoice == "male"
  if conditionRepository[conditionIndex][:display] == "Breast Cancer"
    conditionIndex = rand(conditionRepository.count - 4) - 1 #Note the "conditionRepository.count - 4" is because the last 4 conditions in the repository can only apply to patients with certain attributes (gender/alcholic tendencies/past surgeries)
    if conditionRepository[conditionIndex][:display] == "Breast Cancer"
      conditionIndex = rand(conditionRepository.count - 4) - 1 #Note the "conditionRepository.count - 4" is because the last 4 conditions in the repository can only apply to patients with certain attributes (gender/alcholic tendencies/past surgeries)
    end
  end
else
  if conditionRepository[conditionIndex][:display] == "Prostate Cancer"
    conditionIndex = rand(conditionRepository.count - 4) - 1 #Note the "conditionRepository.count - 4" is because the last 4 conditions in the repository can only apply to patients with certain attributes (gender/alcholic tendencies/past surgeries)
    if conditionRepository[conditionIndex][:display] == "Prostate Cancer"
      conditionIndex = rand(conditionRepository.count - 4) - 1 #Note the "conditionRepository.count - 4" is because the last 4 conditions in the repository can only apply to patients with certain attributes (gender/alcholic tendencies/past surgeries)
    end
  end
end

#Diabetes and hypertension get their own specification because they are directly related to the observations patientGlucose and bloodPressure (respectively)
#These first two lines are just setting the variables for the first time through the condition-creating loop
if conditionCounter == 1
  hasDiabetes = false
  hasHypertension = false
else
  $allConditions.each do |condition|
    if condition.code.text == "Diabetes"
      hasDiabetes = true
    end
    if condition.code.text == "Hypertension"
      hasHypertension = true
    end
  end
end

#This 'if/else' statement ensures that patients have the Diabetes condition if and only if they have high blood glucose levels (decided in observations)
if hasDiabetes == false
  if patientGlucose.valueQuantity.value >= 200
    conditionIndex = 1
    hasDiabetes = true
  else
    if conditionIndex == 1
      conditionIndex = rand(3..conditionRepository.count-4) - 1 #Note the "conditionRepository.count - 4" is because the last 4 conditions in the repository can only apply to patients with certain attributes (gender/alcholic tendencies/past surgeries)
    end
  end
end

#This 'if/else' statement ensures that patients have the Hypertension condition if and only if they have high blood pressure (decided in observations)
if hasHypertension == false
  if bpChoice == "Hypertension"
    if conditionIndex == 1
      hasDiabetes = false
    end
    conditionIndex = 0
    hasHypertension = true
  else
    if conditionIndex == 0
      conditionIndex = rand(3..conditionRepository.count-4) - 1 #Note the "conditionRepository.count - 4" is because the last 4 conditions in the repository can only apply to patients with certain attributes (gender/alcholic tendencies/past surgeries)
    end
  end
end


#This code iterates through the $allConditions array and chooses a new conditionIndex if the patient already had that condition
#Essentially it prevents duplicate conditions
#I had trouble implementing a 'while' loop so for now I have implemented four 'if' statements but there is technically still a miniscule chance that a patient had duplicate conditions
if conditionCounter > 1
  while pastConditionIndices.include?(conditionIndex)
    conditionIndex = rand(2..76)
  end
end

#This code creates the possibility for a post-operative infection, but only after a patient has had a procedure
if conditionCounter == numberOfConditions
  if postOperativeVar == false
    if allProcedures.count > 0
      if rand(20) == 7 #This just creates a 5% chance that a procedure will cause a "Post-Operative Infection"
        numberOfConditions += 1 #This adds a condition so the post-operative infectiondoesn't take up one of the pre-allotted condition slots
        conditionIndex = 80 #This is the condition index for "Post-Operative Infection"
        postOperativeVar = true #This is so a patient does not have several post-operative infections
      end
    end
  end
end

#This code establishes when exactly the condition is diagnosed
dateAssertedVar = Faker::Date.between(3.years.ago, Date.today)
if conditionIndex == 80
  dateAssertedVar = allProcedures[0].date.end + rand(5..10).days #This is just so the post-operative infection doesn't happen before the operation/procedure
end

if conditionCounter == 1
  earliestDateAsserted = dateAssertedVar
else
  if dateAssertedVar < earliestDateAsserted
    earliestDateAsserted = dateAssertedVar
  end
end

#This code will determine if the patient died from this condition
deathChance = rand(100)
if deathChance < conditionRepository[conditionIndex][:mortalityChance]
  #This pulls information for the condition repository so the time between a condition's assertion and the patient's death is unique to each condition
  case conditionRepository[conditionIndex][:mortalityTime]
  when "day"
    potentialDeceasedDateTime = dateAssertedVar + rand(0..1).days
  when "threeWeeks"
    potentialDeceasedDateTime = dateAssertedVar + rand(15..25).days
  when "twoYears"
    potentialDeceasedDateTime = dateAssertedVar + rand(1..2).years + rand(0..11).months + rand(0..27).days
  when "fourYears"
    potentialDeceasedDateTime = dateAssertedVar + rand(3..4).years + rand(0..11).months + rand(0..27).days
  when "sevenYears"
    potentialDeceasedDateTime = dateAssertedVar + rand(6..7).years + rand(0..11).months + rand(0..27).days
  end
  #This ensures that the potenialDeceasedDateTime is not after today's date because it wouldn't make sense for a patient to have a death date in the future
  if potentialDeceasedDateTime.to_s <= Date.today.to_s
    #If a patient has already died from a different condition, the deceasedDateTime will be only be changed if this condition would cause death sooner
    #Ultimately the patient will have the soonest death date possible
    if mockPatient.deceasedBoolean == true
      if potentialDeceasedDateTime.to_s < mockPatient.deceasedDateTime.to_s
        mockPatient.deceasedDateTime = potentialDeceasedDateTime
        $causeOfDeathVar = conditionRepository[conditionIndex][:display]
      end
    #This code is for patient's that do not have any other fatal conditions
    else
      mockPatient.deceasedBoolean = true
      mockPatient.deceasedDateTime = potentialDeceasedDateTime
      $causeOfDeathVar = conditionRepository[conditionIndex][:display]
    end
  end
end

#The following code adds the conditionIndex to an array that is used in future interations to avoid duplicate conditions
pastConditionIndices.push(conditionIndex)

#This code essentially takes the information from the indexed condition in the repository and translates it to FHIR format
#Conditions are coded with ICD-9 codes
conditionDisplayVar = conditionRepository[conditionIndex][:display]
conditionCodeVar = conditionRepository[conditionIndex][:icd9code]
mockCondition.code = {coding: [{system: "http://hl7.org/fhir/sid/icd-9", code: conditionCodeVar, display: conditionDisplayVar}], text: conditionDisplayVar}
mockCondition.category = {coding: [{system: "http://hl7.org/fhir/condition-category", code: "diagnosis", display: "Diagnosis"}]}
mockCondition.status = "confirmed"
recoveryEstimateVar = conditionRepository[conditionIndex][:recoveryEstimate]

#This is just to initialize, it may be changed
mockCondition.abatementBoolean = false

#This line of code determines the asserted date of the condition
mockCondition.dateAsserted = dateAssertedVar

#The 'if' portion of this 'if/else' statement is for conditions that are either cured are cause immenent death (such as intracranial hemmhoraging)
if conditionRepository[conditionIndex][:healOrDeath] == true
  abatementChanceVar = 100 #Because it is either abated or causes death, it can not linger
  #The following code pulls information from the condition repository as every condition has a unqiue recovery timeline
  if recoveryEstimateVar == "threeYears"
    abatementDateVar = dateAssertedVar + rand(2..4).years + rand(0..11).months + rand(0..27).days
  elsif recoveryEstimateVar == "sixMonths"
    abatementDateVar = dateAssertedVar + rand(5..7).months + rand(0..20).days
  elsif recoveryEstimateVar == "threeMonths"
    abatementDateVar = dateAssertedVar + rand(2..3).months + rand(0..20).days
  elsif recoveryEstimateVar == "week"
    abatementDateVar = dateAssertedVar + rand(6..10).days
  elsif recoveryEstimateVar == "N/A"
    abatementDateVar = nil
  else
    puts "Error: Recovery Estimate for this condition is not supported"
  end
  #This prevents conditions from being recorded as abated if their abatement date is in the future (because that wouldn't make sense
  if abatementDateVar > Date.today
    mockCondition.abatementBoolean = false
  #This prevents a condition from being abated after a patient dies
  elsif abatementDateVar.to_s > mockPatient.deceasedDateTime.to_s
    #The following three lines are just a bug fix, sometimes mockPatient.deceasedDateTime.to_s == "", but the patient is not actually deceased
    if mockPatient.deceasedDateTime.to_s == ""
      mockCondition.abatementBoolean = true
      mockCondition.abatementDate = abatementDateVar
    else
      mockCondition.abatementBoolean = false
    end
  else
    mockCondition.abatementBoolean = true
    mockCondition.abatementDate = abatementDateVar
  end
#The 'else' portion is for all other conditions that can linger without causing death (most chronic conditions)
else
  abatementChanceVar = rand(1..99)
  #The following line pulls information from the condition repository as the chance of abatement is unique for each condition
  if conditionRepository[conditionIndex][:abatementChance] > abatementChanceVar
    if recoveryEstimateVar == "threeYears"
      abatementDateVar = dateAssertedVar + rand(2..4).years + rand(0..11).months + rand(0..27).days
    elsif recoveryEstimateVar == "sixMonths"
      abatementDateVar = dateAssertedVar + rand(5..7).months + rand(0..20).days
    elsif recoveryEstimateVar == "threeMonths"
      abatementDateVar = dateAssertedVar + rand(2..3).months + rand(0..20).days
    elsif recoveryEstimateVar == "week"
      abatementDateVar = dateAssertedVar + rand(6..10).days
    elsif recoveryEstimateVar == "N/A"
      abatementDateVar = nil
    else
      puts "Error: Recovery Estimate for this condition is not supported"
    end
  #The following code ensures that a condition does not have an abatement date in the future or after the patient's deceased date
    if abatementDateVar == nil
      mockCondition.abatementBoolean = false
    else
      if abatementDateVar > Date.today
        mockCondition.abatementBoolean = false
      elsif abatementDateVar.to_s > mockPatient.deceasedDateTime.to_s
        #The following three lines are just a bug fix, sometimes mockPatient.deceasedDateTime.to_s == "", but the patient is not actually deceased
        if mockPatient.deceasedDateTime.to_s == ""
          mockCondition.abatementBoolean = true
          mockCondition.abatementDate = abatementDateVar
        else
          mockCondition.abatementBoolean = false
        end
      else
        mockCondition.abatementBoolean = true
        mockCondition.abatementDate = abatementDateVar
      end
    end
  end
end








#MockEncounters#########################################################################################################################################################################################################################################################################################################
########################################################################################################################################################################################################################################################################################################################

#This method creates a FHIR-format encounter for the patient resource
def createEncounter()
  newEncounter = FHIR::Encounter.new()
end

#This code chooses a random period for the patient's hospital stay that is within the range specific to each condition (found in the condition repository, following the :overnights key)
lowStayPeriod = conditionRepository[conditionIndex][:overnights].split("-").first.to_i
highStayPeriod = conditionRepository[conditionIndex][:overnights].split("-").second.to_i
stayPeriod = rand(lowStayPeriod..highStayPeriod).days + rand(6).hours + rand(60).minutes + rand(60).seconds

#This code creates a FHIR-format encounter resource that corresponds with the previously assigned condition and the date that it was asserted
mockEncounter = createEncounter()
#This 'if/else' statement just creates an identifier depending on if the patient stayed overnight when diagnosed with the condition assigned above
if conditionRepository[conditionIndex][:overnights] == "0"
  mockEncounter.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << "'s visit on " << dateAssertedVar.to_s}]
else
  mockEncounter.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << "'s overnight visit from " << dateAssertedVar.to_s << " to " << (dateAssertedVar + stayPeriod).to_s}]
end

#The varibales in the line below look weird, but that is just because the patient's name is nested in a series of arrays and hashes; this line will look normal when printed to json
mockEncounter.subject = {"display" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " " << mockPatient.name[0].family[0][0]}
#The following line determines the length of the encounter based on how many nights the patient stays at the hospital following the diagnosis
if conditionRepository[conditionIndex][:overnights] == "0"
  mockEncounter.period = {"start" => dateAssertedVar, "end" => dateAssertedVar + rand(6).hours + rand(60).minutes + rand(60).seconds}
else
  mockEncounter.period = {"start" => dateAssertedVar, "end" => dateAssertedVar + stayPeriod.parts[0][1].days}
end
#The following code just identifies whether the encounter has concluded or if it is currently ongoing (based on today's date)
if mockEncounter.period.end <= Date.today
  mockEncounter.status = "finished"
else
  mockEncounter.status = "in-progress"
end
#This line is just a placeholder because we are working with MedStar
mockEncounter.serviceProvider = {"display" => "Medstar Health"}

#This code randomizes readmission, but at this stage it is only a boolean
#If this reAdmission value is true, an additional "reAdmission" encounter will be created later on in the script
reAdmissionPossible = rand(5)
if reAdmissionPossible == 1
  mockEncounter.hospitalization = {"reAdmission" => true}
else
  mockEncounter.hospitalization = {"reAdmission" => false}
end

#This series of code assigns a reason to the encounter
#The 'if/else' statements are just to adjust the wording based on overnight vs nonovernight vists and the gender of the patient
if stayPeriod.parts[0][1].to_i == 0
  #This 'if' statement just determines whether to use 'he' or 'she' in the mock.Encounter.text
  if $genderChoice == "male"
    mockEncounter.reason = {text: "99283 Emergency Department Visit,#{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} came in for a non-overnight visit where he was diagnosed with #{mockCondition.code.text}."}
  else
    mockEncounter.reason = {text: "99283 Emergency Department Visit,#{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} came in for a non-overnight visit where she was diagnosed with #{mockCondition.code.text}."}
  end
else
  #This 'if' statement just determines whether to use 'he' or 'she' in the mock.Encounter.text
  if $genderChoice == "male"
    mockEncounter.reason = {text: "99283 Emergency Department Visit,#{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} stayed for #{stayPeriod.parts[0][1]} nights after being diagnosed with #{mockCondition.code.text}."}
  else
    mockEncounter.reason = {text: "99283 Emergency Department Visit,#{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} stayed for #{stayPeriod.parts[0][1]} nights after being diagnosed with #{mockCondition.code.text}."}
  end
end









#MockProcedures###########################################################################################################################################################################################################################################################################################################
##########################################################################################################################################################################################################################################################################################################################

#This code dictates whether the patient will undergo a procedure depending on how likely/effective surgery is for the specific condition diagnosed
procedurePossibility = rand(1..100)
#The following line pulls information from the condition repository because the chance that a condition requires a procedure/surgery is unique to each condition
if procedurePossibility <= conditionRepository[conditionIndex][:procedureChance]
  #This method creates a FHIR-format procedure for the patient resource
  def createProcedure()
    newProcedure = FHIR::Procedure.new()
  end
  mockProcedure = createProcedure()
  #I had to create a 'procedureNotesVar' in the condition creating portion of this script to avoid a bug
  mockProcedure.encounter = {"display" => "#{mockEncounter.identifier[0].label}"}
  #mockProcedure.status and mockProcedure.type were not recognized, so I nested them in a hash in mockProcedure.notes
  mockProcedure.date = mockEncounter.period
  mockProcedure.date.end = mockProcedure.date.start + rand(3..9).hours
  #The following information (code and display) will be used in printing the JSON file later on
  #The fact that this info is stored in '.notes' is irrelevant, I just needed somewhere to put it
  mockProcedure.notes = "code: " << conditionRepository[conditionIndex][:procedureCode] << ", display: " << conditionRepository[conditionIndex][:procedureCodeName]

  #The following code takes into account the procedureSuccess rate and increases the chance of abatement accordingly
  if mockCondition.abatementBoolean == false
    if conditionRepository[conditionIndex][:abatementChance] <= abatementChanceVar
      unless conditionRepository[conditionIndex][:abatementChance] == 0
        procedureAbatementPossibility = rand(1..100)
        if procedureAbatementPossibility <= conditionRepository[conditionIndex][:procedureSuccess]
          mockCondition.abatementBoolean = true
          if recoveryEstimateVar == "threeYears"
            abatementDateVar = dateAssertedVar + rand(2..4).years + rand(0..11).months + rand(0..27).days
          elsif recoveryEstimateVar == "sixMonths"
            abatementDateVar = dateAssertedVar + rand(5..7).months + rand(0..20).days
          elsif recoveryEstimateVar == "threeMonths"
            abatementDateVar = dateAssertedVar + rand(2..3).months + rand(0..20).days
          elsif recoveryEstimateVar == "week"
            abatementDateVar = dateAssertedVar + rand(6..10).days
          else
            return "Error: Recovery Estimate for this condition is not supported"
          end
        #The following code ensures that a condition does not have an abatement date in the future or after the patient's deceased date
          if abatementDateVar > Date.today
            mockCondition.abatementBoolean = false
          elsif abatementDateVar.to_s > mockPatient.deceasedDateTime.to_s
            #The following three lines are just to fix a bug where the patient is incorrectly decided 'deceased' but not given a deceased time
            if mockPatient.deceasedDateTime.to_s == ""
              mockCondition.abatementBoolean = true
              mockCondition.abatementDate = abatementDateVar
            else
              #The following line prevents a condition from being marked as abated if its abatement date is after the patient's deceased date
              mockCondition.abatementBoolean = false
            end
          else
            mockCondition.abatementBoolean = true
            mockCondition.abatementDate = abatementDateVar
          end
        else
          mockCondition.abatementBoolean = false
        end
      end
    end
  end
end








#CheckUp Encounters#######################################################################################################################################################################################################################################################################################################
##########################################################################################################################################################################################################################################################################################################################

#The following array will be used to hold all non-diagnosis encounters, which will be added to AllEncounters later on
allExtraEncounters = []
#The following section of code creates a checkup encounter if the condition requires such
#This section is first divided into an 'if/else' statement that separates 'chemotherapy' from the rest of the of the checkUp cases
if conditionRepository[conditionIndex][:checkUp] == "chemotherapy"
  #This method creates a FHIR-format encounter for the patient resource
  def createEncounter()
    newEncounter = FHIR::Encounter.new()
  end

  #The following code is just an algorithm to determine the number of chemotherapy treatments a patient will undergo between the date of diagnosis until today (if the patient dies or the cancer is cured, all appointments after death/cure will be deleted later in the script)
  chemotherapyTiming = []
  #The following line determiens the number of years the patient undergoes chemotherapy
  chemotherapyTiming << (Date.today.to_s[3].to_i - mockCondition.dateAsserted.to_s[3].to_i)
  #The following line determiens the number of months the patient undergoes chemotherapy
  chemotherapyTiming << (Date.today.to_s[5..6].to_i - mockCondition.dateAsserted.to_s[5..6].to_i)
  #The following line determiens the number of days the patient undergoes chemotherapy
  chemotherapyTiming << (Date.today.to_s[8..9].to_i - mockCondition.dateAsserted.to_s[8..9].to_i)
  #The following line converts the number of years and months to the number of chemotherapy treatments
  numberOfChemoTreatments = chemotherapyTiming[0]*12 + chemotherapyTiming[1]
  #The following line just subtracts one from numberOfChemoTreatments if the month hasn't been completed yet (example: cancer is diagnosed August 15th, current date is November 8th therefore there is only one completed month elapsed)
  if chemotherapyTiming[2] < 0
    numberOfChemoTreatments -= 1
  end
  #This just initializes a variable to count the number of iterations through the chemo-encounter-creating loop
  chemoCounter = 0
  #The following loop creates Chemotherapy Treatment Encounters
  begin
  numberOfChemoTreatments.times do
    chemoCounter += 1
    mockChemo =
    ()
    #Chemotherapy treatments are to happen monthly within a +/-2 of 2 days so it isn't robot-like
    #Doctors may suggest weekly treatments for some cancers, but that would make for potentially hundreds of encounters, especially if a patient happens to be assigned two types of cancer (very small chance, but possible) so chemotherapy treatments are monthly
    chemotherapyDateVar = mockCondition.dateAsserted + chemoCounter.months + rand(-2..2).days
    mockChemo.period = {"start" => chemotherapyDateVar}
    mockChemo.period["end"] = mockChemo.period.start + rand(1..3).hours + rand(0..60).minutes
    mockChemo.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << "'s visit on " << mockChemo.period.start.to_s}]
    mockChemo.subject = {"display" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " " << mockPatient.name[0].family[0][0]}
    #The following line is just a placeholder because our primary sponsor at the time is MedStar
    mockChemo.serviceProvider = {"display" => "Medstar Health"}
    #The following line negates the possibility of creating a reAdmission for a chemotherapy encounter, but this does not negate the possibilty for a reAdmission regarding the cancer diagnosis itself
    mockChemo.hospitalization = {"reAdmission" => false}
    if $genderChoice == "male"
      mockChemo.reason = {text: "96411 Chemotherapy Treatment, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} came in for a routine chemotherapy treatment regarding his #{mockCondition.code.text}."}
    else
      mockChemo.reason = {text: "96411 Chemotherapy Treatment, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} came in for a routine chemotherapy treatment regarding her #{mockCondition.code.text}."}
    end
    #The following block just decides if the encounter is completed based on today's date
    if mockChemo.period.end <= Date.today
      mockChemo.status = "finished"
    else
      mockChemo.status = "in-progress"
    end
    allExtraEncounters << mockChemo
  end
#The following rescue clause is to catch a rare error where 'period' is not recognized as a field
#The solution is just to delete all chemo treatments and continue with the script (because it possible that some patients would choose not to undergo chemotherapy anyway)
rescue
  allExtraEncounters.clear
end
#The following 'else' block includes all other types of checkUp encounters other than chemotherapy
#The code was written this way because chemotherapy is a repetitive encounter and all other types are just one-time encounters
else
  #The following line catches the possibility that a condition has no possible CheckUp encounter
  unless conditionRepository[conditionIndex][:checkUp] == "none"
    #The following line catches the possibility that the checkup is only need if the patient undergoes surgery, but the patient does not undergo surgery so there is no need for a checkup encounter
    unless (conditionRepository[conditionIndex][:checkUp].to_s[0..10] == "ifProcedure") && (procedurePossibility > conditionRepository[conditionIndex][:procedureChance])
      #This code creates a FHIR-format encounter resource
      def createEncounter()
        newEncounter = FHIR::Encounter.new()
      end
      mockCheckup = createEncounter()
      #The code to retrieve the patient's name on the following line is a  bit weird, but that's just because the name is nested in a series of hashes and arrays
      mockCheckup.subject = {"display" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " " << mockPatient.name[0].family[0][0]}
      mockCheckup.serviceProvider = {"display" => "Medstar Health"}
      mockCheckup.hospitalization = {"reAdmission" => false}
      #The following line checks the ':checkUp' field in the condition repository because the 'checkUp' protocol for each condition is different
      case conditionRepository[conditionIndex][:checkUp]
      #There are three possible checkups (apart from chemotherapy)
      when "weekLater"
        mockCheckup.period = {"start" => mockEncounter.period.end + rand(5..10).days}
        mockCheckup.period["end"] = mockCheckup.period.start + rand(1..3).hours + rand(0..60).minutes
        mockCheckup.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << "'s visit on " << mockCheckup.period.start.to_s}]
        #The following 'if/else' statement is just to determine whether to use 'he' or 'she' in the short text
        if $genderChoice == "male"
          mockCheckup.reason = {text: "99215 Office Outpatient Visit, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} came in for a check-up appointment regarding his #{mockCondition.code.text}."}
        else
          mockCheckup.reason = {text: "99215 Office Outpatient Visit, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} came in for a check-up appointment regarding her #{mockCondition.code.text}."}
        end
      #The following case covers conditions that only require a checkup if surgery was performed
      when "ifProcedure-weekLater"
        mockCheckup.period = {"start" => mockEncounter.period.end + rand(5..10).days}
        mockCheckup.period["end"] = mockCheckup.period.start + rand(1..3).hours + rand(0..60).minutes
        mockCheckup.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << "'s visit on " << mockCheckup.period.start.to_s}]
        if $genderChoice == "male"
          mockCheckup.reason = {text: "99024 Postoperative Follow-Up Visit, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} came in for a check-up appointment for a past surgery regarding his #{mockCondition.code.text}."}
        else
          mockCheckup.reason = {text: "99024 Postoperative Follow-Up Visit, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} came in for a check-up appointment for a past surgery regarding her #{mockCondition.code.text}."}
        end
      #The following case covers specfically cast removals for broken bones
      when "ifProcedure-CastRemoval"
        mockCheckup.period = {"start" => mockEncounter.period.end + rand(1..2).months + rand(0..30).days}
        mockCheckup.period["end"] = mockCheckup.period.start + rand(1..3).hours + rand(0..60).minutes
        if $genderChoice == "male"
          mockCheckup.reason = {text: "29705 Cast Removal, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} came in for a routine appointment to remove his cast."}
        else
          mockCheckup.reason = {text: "29705 Cast Removal, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0]} came in for a routine appointment to remove her cast."}
        end
      end
      #The following block just decides if the encounter is completed based on today's date
      if mockCheckup.period.end <= Date.today
        mockCheckup.status = "finished"
      else
        mockCheckup.status = "in-progress"
      end
      #The following line adds the checkUp encounter to the allExtraEncounters array that is added to the allEncounters array later which is then printed to JSON and then posted to the server
      #Adding these encounters to AllEncounters now would mess up the iteration that deletes post-mortem diagnosis encounters if a patient dies
      allExtraEncounters << mockCheckup
    end
  end
end









#MockMedications##########################################################################################################################################################################################################################################################################################
#########################################################################################################################################################################################################################################################################################################
def createMedication()
  newMedication = FHIR::Medication.new()
end

#This is the repository of medications; these are associated with conditions using the :medication_id tag within the CONDITION repository (not the following medication repository)
#There are more conditions than medications because some conditions do not require medications and there are a few conditions that use the same medication
#If the medication is taken as needed, the rate is the maximum suggested dosage
#The rate symbol has seemingly unecessary spaces, but they are needed for cutting the string into pieces for the MedicationStatement
medicationRepository = [
  {medication_id: 1,  rxNormCode: "997224",  brandName: "Aricept",                     brand?: true,  "tradeName" => "Donepezil Hydrochloride 10mg Oral Tablet",                              asNeeded: false, rate: "10 mg / day"},
  {medication_id: 2,  rxNormCode: "141962",  brandName: "N/A",                         brand?: false, "tradeName" => "Azithromycin 250mg Oral Capsule",                                       asNeeded: false, rate: "500 mg / day"},
  {medication_id: 3,  rxNormCode: "104376",  brandName: "Zestril",                     brand?: true,  "tradeName" => "Lisinopril 5mg Oral Tablet",                                            asNeeded: false, rate: "5 mg / day"},
  {medication_id: 4,  rxNormCode: "860998",  brandName: "Fortamet",                    brand?: true,  "tradeName" => "Metformin Hydrochloride 1000mg Extended Release Oral Tablet",           asNeeded: false, rate: "1000 mg / day"},
  {medication_id: 5,  rxNormCode: "1186297", brandName: "XALATAN Ophthalmic Solution", brand?: true,  "tradeName" => "N/A",                                                                   asNeeded: false, rate: "1 drop / day"},
  {medication_id: 6,  rxNormCode: "369070",  brandName: "Tylenol",                     brand?: true,  "tradeName" => "Acetaminophen 650mg Tablet",                                            asNeeded: true,  rate: "3900 mg / day"},
  {medication_id: 7,  rxNormCode: "261315",  brandName: "TamilFlu",                    brand?: true,  "tradeName" => "Oseltamivir 75mg Oral Tablet",                                          asNeeded: false, rate: "150 mg / day"},
  {medication_id: 8,  rxNormCode: "104377",  brandName: "Zestril",                     brand?: true,  "tradeName" => "Lisinopril 10mg Oral Tablet",                                           asNeeded: false, rate: "10 mg / day"},
  {medication_id: 9,  rxNormCode: "904421",  brandName: "Fosamax",                     brand?: true,  "tradeName" => "Alendronate 10mg Oral Tablet",                                          asNeeded: false, rate: "10 mg / day"},
  {medication_id: 10, rxNormCode: "644300",  brandName: "Lucentis",                    brand?: true,  "tradeName" => "Ranibizumab Injectable Solution",                                       asNeeded: false, rate: "0.5 mg / month"},
  {medication_id: 11, rxNormCode: "617310",  brandName: "N/A",                         brand?: false, "tradeName" => "Atorvastatin 20mg Oral Tablet",                                         asNeeded: false, rate: "20 mg / day"},
  {medication_id: 12, rxNormCode: "197517",  brandName: "N/A",                         brand?: false, "tradeName" => "Clarithromycin 500mg Oral Tablet",                                      asNeeded: false, rate: "500 mg / day"},
  {medication_id: 13, rxNormCode: "966180",  brandName: "Levothroid",                  brand?: true,  "tradeName" => "Levothyroxine Sodium 0.1mg Oral Tablet",                                asNeeded: false, rate: "0.1 mg / day"},
  {medication_id: 14, rxNormCode: "849612",  brandName: "Bifera",                      brand?: true,  "tradeName" => "FE HEME Polypeptide 6mg/Polysaccharide Iron Complex 22 MG Oral Tablet", asNeeded: false, rate: "6 mg / day"},
  {medication_id: 15, rxNormCode: "198145",  brandName: "N/A",                         brand?: false, "tradeName" => "Prednisone 10mg Oral Tablet",                                           asNeeded: false, rate: "10 mg / day"},
  {medication_id: 16, rxNormCode: "902622",  brandName: "Dexilant",                    brand?: true,  "tradeName" => "Dexlansoprazole 30mg",                                                  asNeeded: false, rate: "30 mg / day"},
  {medication_id: 17, rxNormCode: "968177",  brandName: "Asclera",                     brand?: true,  "tradeName" => "Polidocanol 5mg/mL",                                                    asNeeded: false, rate: "10 mL / week"},
  {medication_id: 18, rxNormCode: "203948",  brandName: "Amoxil",                      brand?: true,  "tradeName" => "Amoxicillin 250mg Oral Capsule",                                        asNeeded: false, rate: "1000 mg / day"},
  {medication_id: 19, rxNormCode: "197540",  brandName: "N/A",                         brand?: false, "tradeName" => "Colchicine 0.5mg Oral Tablet",                                          asNeeded: false, rate: "0.5 mg / day"},
  {medication_id: 20, rxNormCode: "1247761", brandName: "Colace",                      brand?: true,  "tradeName" => "Docusate Sodium 50mg Oral Capsule",                                     asNeeded: true,  rate: "300 mg / day"},
  {medication_id: 21, rxNormCode: "978013",  brandName: "Imodium",                     brand?: true,  "tradeName" => "Loperamide Hydrochloride 2mg Oral Capsule",                             asNeeded: true,  rate: "16 mg / day"},
  {medication_id: 22, rxNormCode: "197832",  brandName: "N/A",                         brand?: false, "tradeName" => "Isoniazid 300mg Oral Tablet",                                           asNeeded: false, rate: "300 mg / day"},
  {medication_id: 23, rxNormCode: "316812",  brandName: "N/A",                         brand?: false, "tradeName" => "Thiamine 50mg",                                                         asNeeded: false, rate: "50 mg / day"},
  {medication_id: 24, rxNormCode: "562918",  brandName: "Sumycin",                     brand?: true,  "tradeName" => "Tetracycline 500mg",                                                    asNeeded: false, rate: "500 mg / day"},
  {medication_id: 25, rxNormCode: "317364",  brandName: "N/A",                         brand?: false, "tradeName" => "Erythromycin 250mg",                                                    asNeeded: false, rate: "250 mg / day"},
  {medication_id: 26, rxNormCode: "884319",  brandName: "Zosyn",                       brand?: true,  "tradeName" => "Piperacillin Injectable Solution",                                      asNeeded: false, rate: "15 g / day"},
  {medication_id: 27, rxNormCode: "858123",  brandName: "Firmagon",                    brand?: true,  "tradeName" => "Degarelix Injectable Solution",                                         asNeeded: false, rate: "80 g / month"},
  {medication_id: 28, rxNormCode: "371664",  brandName: "N/A",                         brand?: false, "tradeName" => "Cyclophosphamide Oral Tablet",                                          asNeeded: false, rate: "300 mg / day"},
  {medication_id: 29, rxNormCode: "349472",  brandName: "N/A",                         brand?: false, "tradeName" => "Gefitinib 250mg Oral Tablet",                                           asNeeded: false, rate: "250 mg / day"},
  {medication_id: 30, rxNormCode: "544557",  brandName: "Avastin",                     brand?: true,  "tradeName" => "Bevacizumab Injectable Solution",                                       asNeeded: false, rate: (patientWeightInKg*10).to_s << " mg / week"}, #This should not be administered until 28 days after surgery(encounter)
  {medication_id: 31, rxNormCode: "1094839", brandName: "Yervoy",                      brand?: true,  "tradeName" => "Ipilimumab Injectable Solution",                                        asNeeded: false, rate: (patientWeightInKg*3).to_s << " mg / month"}, #This should only be taken for four months
  {medication_id: 32, rxNormCode: "615978",  brandName: "Nexavar",                     brand?: true,  "tradeName" => "Sorafenib Oral Tablet",                                                 asNeeded: true,  rate: "400 mg / day"},
  {medication_id: 33, rxNormCode: "858748",  brandName: "Actigall",                    brand?: true,  "tradeName" => "Ursodiol Oral Product",                                                 asNeeded: false, rate: (patientWeightInKg*10).to_s << " mg / day"},
  {medication_id: 34, rxNormCode: "352219",  brandName: "Vfend",                       brand?: true,  "tradeName" => "Voriconazole 200mg Oral Tablet",                                        asNeeded: false, rate: "200 mg / day"},
  {medication_id: 35, rxNormCode: "630974",  brandName: "N/A",                         brand?: false, "tradeName" => "Sodium Bicarbonate 500mg",                                              asNeeded: false, rate: "500 mg / day"},
  {medication_id: 36, rxNormCode: "824190",  brandName: "Augmentin",                   brand?: true,  "tradeName" => "Amoxicillin (500mg) & Clavulanate (125mg)",                             asNeeded: false, rate: "500 mg / day"},
  {medication_id: 37, rxNormCode: "205483",  brandName: "Dritho-Scalp",                brand?: true,  "tradeName" => "Anthralin",                                                             asNeeded: true,  rate: "10 mL / day"},
  {medication_id: 38, rxNormCode: "363298",  brandName: "Fludara",                     brand?: true,  "tradeName" => "Fludarabine Injectable Solution",                                       asNeeded: false, rate: "25 mg / week"},
  {medication_id: 39, rxNormCode: "854878",  brandName: "Ambien",                      brand?: true,  "tradeName" => "Zolpidem Tartrate Oral Tablet",                                         asNeeded: true,  rate: "5 mg / day"},
  {medication_id: 40, rxNormCode: "213321",  brandName: "Maxalt",                      brand?: true,  "tradeName" => "Rizatriptan Benzoate Oral Tablet",                                      asNeeded: true,  rate: "5 mg / day"},
  {medication_id: 41, rxNormCode: "866307",  brandName: "Tegretol",                    brand?: true,  "tradeName" => "Carbamazepine 400mg Oral Tablet",                                       asNeeded: false, rate: "800 mg / day"},
  {medication_id: 42, rxNormCode: "834137",  brandName: "PeriodGard",                  brand?: true,  "tradeName" => "Chlorhexidine Gluconate Mouthwash",                                     asNeeded: false, rate: "50 mg / day"},
  {medication_id: 43, rxNormCode: "584503",  brandName: "AuroGuard",                   brand?: true, "tradeName" => "Antipyrine/Benzocaine Otic Solution",                                    asNeeded: true,  rate: "10 drops / day"},
  {medication_id: 44, rxNormCode: "208416",  brandName: "Bactrim",                     brand?: true, "tradeName" => "Sulfamethoxazole/Trimethoprim Oral Tablet",                              asNeeded: false, rate: "1000 mg / day"},
  {medication_id: 45, rxNormCode: "1052982", brandName: "Bayer Aspirin",               brand?: true, "tradeName" => "Aspirin 500mg Oral Powder",                                              asNeeded: true,  rate: "4000 mg / day"},
  {medication_id: 46, rxNormCode: "352307",  brandName: "Abilify",                     brand?: true, "tradeName" => "Aripiprazole 10mg Oral Tablet",                                          asNeeded: false, rate: "10 mg / day"}
    ]

  #This code creates a medication and then takes the information from the medication repository that corresponds to the previously created disease
  #A medication is created even if the condition does not require a medication-- it is just a placeholder and will be deleted later
  mockMedication = createMedication()

  #This 'unless' statement is for conditions that don't have medications (in which case the loop will omit the medication and MedicationStatement sections)
  #Later on in the script, these place-holding medications will be deleted based on the fact that they were not assigned a '.kind' field
  unless conditionRepository[conditionIndex][:medication_id] == 0
    begin
      mockMedication.isBrand = medicationRepository[conditionRepository[conditionIndex][:medication_id]-1][:brand?]
    rescue
      #Sometimes ruby does not recognize the [:brand?] but since it is an insignificant detail I thought it would be okay to allow the script to continue
    end
    mockMedication.kind = "Product"

    #The following 'if/else' statement just determines whether to use the :brandName field or the "tradeName" field for the 'name' field
    if mockMedication.isBrand == true
      mockMedication.name = medicationRepository[conditionRepository[conditionIndex][:medication_id]-1][:brandName]
      mockMedication.code = {coding: [{system: "http://www.nlm.nih.gov/research/umls/rxnorm/", code: medicationRepository[conditionRepository[conditionIndex][:medication_id]-1][:rxNormCode], display: medicationRepository[conditionRepository[conditionIndex][:medication_id]-1][:brandName] << " " << "(Trade Name: " << medicationRepository[conditionRepository[conditionIndex][:medication_id]-1]["tradeName"] << ")"}]}
    else
      mockMedication.name = medicationRepository[conditionRepository[conditionIndex][:medication_id]-1]["tradeName"]
      mockMedication.code = {coding: [{system: "http://www.nlm.nih.gov/research/umls/rxnorm/", code: medicationRepository[conditionRepository[conditionIndex][:medication_id]-1][:rxNormCode], display: medicationRepository[conditionRepository[conditionIndex][:medication_id]-1]["tradeName"]}], text: medicationRepository[conditionRepository[conditionIndex][:medication_id]-1]["tradeName"].to_s}
    end

    #These variables are used in the Medication Statement section
    mockMedicationNameVar = mockMedication.name
    mockMedicationAsNeededVar = medicationRepository[conditionRepository[conditionIndex][:medication_id]-1][:asNeeded]
    mockMedicationRateVar = medicationRepository[conditionRepository[conditionIndex][:medication_id]-1][:rate]

    #This is the end to the 'unless' statement that skipped the assignment of medication attributes if there is no medication for the assigned condition
  end








#MedicationStatement####################################################################################################################################################################################################################################################################################################
########################################################################################################################################################################################################################################################################################################################
  def createMedicationStatement()
    newMedicationStatement = FHIR::MedicationStatement.new()
  end

  #This code creates a medication statement that summarizes all of the assigned medications and whether or not the prescriptions are still active
  #A medication statement is created even if the condition does not require a medication-- it is just a placeholder and will be deleted later
  mockMedicationStatement = createMedicationStatement()

  #This 'unless' statement filters out all place-holding medication statements
  #Later on in the script, these place-holding medication statements will be deleted based on the fact that they were not assigned a '.wasNotGiven' field
  unless conditionRepository[conditionIndex][:medication_id] == 0

    #This patient generator does not generate medications that were not given to the patient
    mockMedicationStatement.wasNotGiven = false
    #If the condition for which the medication was given is still active, the medication statement does not have an end date
    #The following dateAssertedVar variable was created in the condition selection/assignment section
    if mockCondition.abatementBoolean == true
      mockMedicationStatement.whenGiven = {"start" => dateAssertedVar, "end" => mockCondition.abatementDate}
    else
      #Note that if the patient dies, the medicationStatement will not necessarily have an 'end' date in the '.whenGiven' field just because the patient died
      mockMedicationStatement.whenGiven = {"start" => dateAssertedVar}
    end
    mockMedicationStatement.medication = {"display" => "#{mockMedicationNameVar}"}
    mockMedicationStatement.dosage = [{asNeededBoolean: mockMedicationAsNeededVar, rate: {numerator: {value: mockMedicationRateVar.split(" ").first.to_f, units: mockMedicationRateVar.split(" ").second}, denominator: {value: 1, units: mockMedicationRateVar.split(" ").last}}}]

  #The following 'end' closes the 'unless' statement that omits medicationStatements (not the creation of the medicationStatement, just the addition of all the details) when the condition has no medication
  end








#Adding Condition/Medication/Statement/Encounter to Profile Arrays##################################################################################################################################################################################################################################################################################################
####################################################################################################################################################################################################################################################################################################################################################################
#This series of code adds each resource created in the large loop (condition/encounter/medication/medicationStatement) to their respective holding arrays
#These are the arrays that will eventually be printed to JSON and uploaded to the server
#The $allConditions variable is global just to fix a bug that occurred in a loop later in the script
$allConditions << mockCondition
allEncounters << mockEncounter
allMedications << mockMedication
allMedicationStatements << mockMedicationStatement
#The following code only adds the procedure if the procedure was created (unlike medication and medicationStatement)
#For this reason, there are no place-holding procedures and therefore no need to delete them later in the script
if procedurePossibility <= conditionRepository[conditionIndex][:procedureChance]
  allProcedures << mockProcedure
end

#Below is the end of the large 'until' loop that creates the conditions and their corresponding medications and medication statements
end

#The following code was originially implemented to create the possibility for a death due to natural causes, but it causes issues because there is no condition assigned to it
##This code creates the possibility (a 1/30 chance) that the patient dies from natural causes
#unless mockPatient.deceasedBoolean == true
#  unless allEncounters.count == 0
#    naturalDeathChance = rand(30)
#    if naturalDeathChance == 8 #The number 8 is insignificant it's just a random number -- any integer would give a 1/30 chance
#      $causeOfDeathVar = "Natural Causes"
#      mockPatient.deceasedBoolean = true
#      mockPatient.deceasedDateTime = Faker::Date.between(3.years.ago,Date.today)
#    end
#  end
#end

#The following arrays hold all deleted resources
deletedConditions = []
deletedMedications = []
deletedMedicationStatements = []
deletedEncounters = []
deletedProcedures = []

#This code deletes the placeholders in the allMedications and allMedicationsStatements arrays that don't actually contain medications/statements
medDeleterCounter = 0
deletedMedIndices = []
deletedMedications = allMedications.select {|medication| medication.kind == nil} #medication.kind is just a simple field that is nil for each placeholding medication resource, or that contains "Product" for each non-blank medication resource
allMedications = allMedications.select {|medication| medication.kind == "Product"}
deletedMedicationStatements = allMedicationStatements.select {|medicationStatement| medicationStatement.whenGiven == nil} #medicationStatement.whenGiven is just a simple field that is nil for each placeholding medication resource, or that contains a 'start' and an 'end' for each non-blank medication resource
allMedicationStatements = allMedicationStatements.select {|medicationStatement| medicationStatement.whenGiven.present? == true}

#The following series of code deletes conditions and their corresponding medications/medicationStatements/encounters if the condition was asserted after the patient died
unless $allConditions.count == 0
  if mockPatient.deceasedDateTime
    #This code removes conditions/medications that were created, but occured before the patient died (mockPatient.deceasedDateTime)
    deletedConditionIteratorCounter = 0
    #The following loop deletes potential condition abatement dates after the patient has died
    #It also sets the medicationStatement.whenGiven.end field to nil because we shouldn't know when the prescription (statement) would have ended
    $allConditions.each do |condition|
      if condition.abatementDate.to_f > mockPatient.deceasedDateTime.to_f
        $allConditions[deletedConditionIteratorCounter].abatementDate = nil
        $allConditions[deletedConditionIteratorCounter].abatementBoolean = false
        if allMedicationStatements[deletedConditionIteratorCounter].present?
          if allMedicationStatements[deletedConditionIteratorCounter].whenGiven.present?
            allMedicationStatements[deletedConditionIteratorCounter].whenGiven.end = nil
          end
        end
      end
      #The following line is placed outside the 'if' statement so the counter will increase even if the condition is not deleted
      deletedConditionIteratorCounter += 1
    end

    #The following series of code selects all conditions/medicationStatements/encounters that occur BEFORE the patient has died
    #It essentially deletes everything that occurs after the patient dies
    #The deleted resources are stored in respectively-named arrays for testing/debugging purposes
    deletedConditions = $allConditions.select {|condition| condition.dateAsserted > mockPatient.deceasedDateTime}
    $allConditions = $allConditions.select {|condition| condition.dateAsserted <= mockPatient.deceasedDateTime}
    deletedMedicationStatements = allMedicationStatements.select {|medicationStatement| medicationStatement.whenGiven.start > mockPatient.deceasedDateTime}
    allMedicationStatements = allMedicationStatements.select {|medicationStatement| medicationStatement.whenGiven.start <= mockPatient.deceasedDateTime}
    deletedEncounters = allEncounters.select {|encounter| encounter.period.start > mockPatient.deceasedDateTime}
    allEncounters = allEncounters.select {|encounter| encounter.period.start <= mockPatient.deceasedDateTime}
    deletedProcedures = allProcedures.select {|procedure| procedure.date.start > mockPatient.deceasedDateTime}
    allProcedures = allProcedures.select {|procedure| procedure.date.start <= mockPatient.deceasedDateTime}
  end
end

#The following code deletes medications that were assigned for a condition that occured after the patient died
#Because medications are not assigned a date, all medications are checked against the remaining medication statements
#If the medicationStatement was deleted, the corresponding medication will be deleted in the following loop
allMedications.each do |medication|
  medicationStatementBeganAfterDeath = false
  deletedMedicationStatements.each do |deletedMedicationStatement|
    if medication.name == deletedMedicationStatement.medication
      medicationStatementBeganAfterDeath = true
    end
  end
  if medicationStatementBeganAfterDeath == true
    deletedMedications.push(medication)
    allMedications.delete(medication)
  end
end









#MockExtraEncounters##################################################################################################################################################################################################################################################################################################
#####################################################################################################################################################################################################################################################################################################################

#This code creates 'extra' encounters that represent yearly physicals (not necessarily related to a disease, or a hospital visit)
#This first series of code just determines how many years the patient was 'eligible' for physicals (how many years they were in the system and still alive)
if numberOfConditions == 0
  #The 'earliestEncounterDate' variable is used to determine when the patient's observations should be listed as first recorded
  earliestEncounterDate = Faker::Date.between(3.years.ago,Date.today)
else
  earliestEncounterDate = earliestDateAsserted - rand(2..4).months - rand(0..30).days
end
#The following code determines how many yearly physical the patient will have based on how long ago their first encounter was and if they died
if mockPatient.deceasedBoolean == true
  #This converts the year portion of the dates to integers and subtracts them
  numberOfExtraEncounters = mockPatient.deceasedDateTime.to_s[0..3].to_i - earliestEncounterDate.to_s[0..3].to_i
  #I think the following line was just to fix a bug
  unless mockPatient.deceasedDateTime == nil
    #The following series of code subtracts one from the number of physicals if current month/day is before the first encounter month/day (as if the year hasn't rolled over yet)
    if earliestEncounterDate.to_s[5..9] > mockPatient.deceasedDateTime.to_s[5..9]
      numberOfExtraEncounters -= 1
    end
  end
  #If the patient is not deceased, the sole factor is when the patient was first entered into the system
else
  numberOfExtraEncounters = Date.today.to_s[0..3].to_i - earliestEncounterDate.to_s[0..3].to_i + 1
  #The following series of code subtracts one from the number of physicals if current month/day is before the first encounter month/day (as if the year hasn't rolled over yet)
  if earliestEncounterDate.to_s[5..9] > Date.today.to_s[5..9]
    numberOfExtraEncounters -= 1
  end
end

#This ensures that the patient has at least one encounter
if numberOfExtraEncounters < 1
  numberOfExtraEncounters = 1
end

#The following code actually creates the yearly physicals (after it is decided how many to create)
extraEncounterCounter = 0
#This is the beginning of the loop that is run as many times as previously decided (each iteration creates a yearly physical)
until extraEncounterCounter == numberOfExtraEncounters
  extraEncounterCounter += 1
  def createEncounter()
    newEncounter = FHIR::Encounter.new()
  end
  mockExtraEncounter = createEncounter()
  #The following line sets the physicals a year apart within +/-10 days
  extraEncounterDate = earliestEncounterDate + (extraEncounterCounter-1).years + rand(-10..10).days
  mockExtraEncounter.subject = {"display" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " " << mockPatient.name[0].family[0][0].split(" ").first.chomp}
  #The following line sets yearly physicals to not take longer than three hours
  mockExtraEncounter.period = {"start" => extraEncounterDate, "end" => extraEncounterDate + rand(2).hours + rand(60).minutes + rand(60).seconds}
  mockExtraEncounter.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << "'s yearly physical on " << mockExtraEncounter.period.start.to_s}]
  #I have set it so patient's cannot be re-admitted for yearly physicals because that wouldn't make very much sense
  mockExtraEncounter.hospitalization = {"reAdmission" => false}
  #The following field ('.reason.text') is spliced later in the script when the encounter in written to a JSON file
  #It is broken up using the comma into a 'code' section and then a 'text' field
  mockExtraEncounter.reason = {text: "2010F Vital Signs Recorded,#{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0].split(" ").first.chomp} came in for a yearly physical."}
  mockExtraEncounter.serviceProvider = {"display" => "Medstar Health"}
  #This series of code just uses today's date to determine if the encounter is finished or still in-progress (most will be finished)
  if mockExtraEncounter.period.end <= Date.today
    mockExtraEncounter.status = "finished"
  else
    mockExtraEncounter.status = "in-progress"
  end
  allExtraEncounters << mockExtraEncounter
end

allConditionNameExtractions = []
#This code creates 'extra' encounters that are readmissions for previous encounters/diagnoses
readmissionCounter = 0
#The following loop iterates through all encounters and checks if the 'reAdmission' field is true in which case it creates another reAdmission encounter
allEncounters.each do |encounter|
  if encounter.hospitalization.reAdmission == true
    mockExtraEncounter = createEncounter()
    mockExtraEncounter.subject = {"display" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " " << mockPatient.name[0].family[0][0].split(" ").first.chomp}
    #The following line sets the reAdmission to occur roughly a month after the diagnosis
    extraEncounterDate = allEncounters[readmissionCounter].period.end + 1.month + rand(-10..10).days
    #The following line sets the duration of the readmission to be only 6 hours
    mockExtraEncounter.period = {"start" => extraEncounterDate, "end" => extraEncounterDate + rand(6).hours + rand(60).minutes + rand(60).seconds}
    #The next few lines of code extracts the name of the condition the reAdmission has to do with
    #There are a few different formats for the encounter.reason.text fields depending on the encounter so there are two possibilites as to which words to extract to determine the condition
    encounterTextVar = allEncounters[readmissionCounter].reason.text.split(" ")
    conditionNameExtraction = encounterTextVar[13..encounterTextVar.count]
    if conditionNameExtraction[0] == "was" || conditionNameExtraction[0] == "being"
      conditionNameExtraction = encounterTextVar[16..encounterTextVar.count]
    end
    #The following 'case' statement is just because conditions can have anywhere between 1 and 5 words
    case conditionNameExtraction.count
    when 1
      mockExtraEncounter.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " was readmitted for " << conditionNameExtraction[0][0..conditionNameExtraction[0].length-2] << " on " << mockExtraEncounter.period.start.to_s[0..9] << "."}]
      mockExtraEncounter.reason = {text: "99024 Post-Operative Follow-Up, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0].split(" ").first.chomp} came back in for further medical attention regarding a past diagnosis of " << conditionNameExtraction[0]}
    when 2
      mockExtraEncounter.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " was readmitted for " << conditionNameExtraction[0] << " " << conditionNameExtraction[1][0..conditionNameExtraction[1].length-2] << " on " << mockExtraEncounter.period.start.to_s[0..9] << "."}]
      mockExtraEncounter.reason = {text: "99024 Post-Operative Follow-Up, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0].split(" ").first.chomp} came back in for further medical attention regarding a past diagnosis of " << conditionNameExtraction[0] << " " << conditionNameExtraction[1]}
    when 3
      mockExtraEncounter.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " was readmitted for " << conditionNameExtraction[0] << " " << conditionNameExtraction[1] << " " << conditionNameExtraction[2][0..conditionNameExtraction[2].length-2] << " on " << mockExtraEncounter.period.start.to_s[0..9] << "."}]
      mockExtraEncounter.reason = {text: "99024 Post-Operative Follow-Up, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0].split(" ").first.chomp} came back in for further medical attention regarding a past diagnosis of " << conditionNameExtraction[0] << " " << conditionNameExtraction[1] << " " << conditionNameExtraction[2]}
    when 4
      mockExtraEncounter.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " was readmitted for " << conditionNameExtraction[0] << " " << conditionNameExtraction[1] << " " << conditionNameExtraction[2] << " " << conditionNameExtraction[3][0..conditionNameExtraction[3].length-2] << " on " << mockExtraEncounter.period.start.to_s[0..9] << "."}]
      mockExtraEncounter.reason = {text: "99024 Post-Operative Follow-Up, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0].split(" ").first.chomp} came back in for further medical attention regarding a past diagnosis of " << conditionNameExtraction[0] << " " << conditionNameExtraction[1] << " " << conditionNameExtraction[2] << " " << conditionNameExtraction[3]}
    when 5
      mockExtraEncounter.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " was readmitted for " << conditionNameExtraction[0] << " " << conditionNameExtraction[1] << " " << conditionNameExtraction[2] << " " << conditionNameExtraction[3] << conditionNameExtraction[4][0..conditionNameExtraction[4].length-2] << " on " << mockExtraEncounter.period.start.to_s[0..9] << "."}]
      mockExtraEncounter.reason = {text: "99024 Post-Operative Follow-Up, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0].split(" ").first.chomp} came back in for further medical attention regarding a past diagnosis of " << conditionNameExtraction[0] << " " << conditionNameExtraction[1] << " " << conditionNameExtraction[2] << " " << conditionNameExtraction[3] << conditionNameExtraction[4]}
    end
    #The following code checks if the patient is deceased
    if mockPatient.deceasedBoolean == true
      #If the patient is deceased, it only adds the reAdmission encounter if it occured before the patient died
      unless mockExtraEncounter.period.start > mockPatient.deceasedDateTime
        allExtraEncounters << mockExtraEncounter
      end
    else
      allExtraEncounters << mockExtraEncounter
    end
    #The following line prevents a reAdmission encounter for a reAdmission encounter
    mockExtraEncounter.hospitalization = {"reAdmission" => false}
    mockExtraEncounter.serviceProvider = {"display" => "Medstar Health"}
  end
  readmissionCounter += 1
end

#The following code creates a mammogram encounter for those with breast cancer
if hadMammography == false
  #The following code checks for the 'Breast Cancer' condition, and if the pateint has breast cancer, a mammogram encounter is created a few days before the breast cancer diagnosis as if the breast cancer was found in the mammogram
  $allConditions.each do |condition|
    if condition.code.text == "Breast Cancer"
      mockExtraEncounter = createEncounter()
      mockExtraEncounter.subject = {"display" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " " << mockPatient.name[0].family[0][0].split(" ").first.chomp}
      #The mammogram is set to occur a few days before the breast cancer diagnosis as if it was where the signs for breast cancer were first identified
      extraEncounterDate = condition.dateAsserted - rand(2..4).days
      #The mammogram only takes an huor or two
      mockExtraEncounter.period = {"start" => extraEncounterDate, "end" => extraEncounterDate + rand(1..2).hours + rand(60).minutes + rand(60).seconds}
      mockExtraEncounter.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << "'s mammography on " << mockExtraEncounter.period.start.to_s}]
      mockExtraEncounter.reason = {text: "77056 Mammography, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0].split(" ").first.chomp} came in for a Mammography."}
      mockExtraEncounter.serviceProvider = {"display" => "Medstar Health"}
      mockExtraEncounter.hospitalization = {"reAdmission" => true}
      hadMammography = true
      if mockExtraEncounter.period.end <= Date.today
        mockExtraEncounter.status = "finished"
      else
        mockExtraEncounter.status = "in-progress"
      end
      if mockPatient.deceasedBoolean == true
        unless mockExtraEncounter.period.start > mockPatient.deceasedDateTime
          allExtraEncounters << mockExtraEncounter
        end
      else
        allExtraEncounters << mockExtraEncounter
      end
    end
  end
end

#The following code creates a colonoscopy encounter for those with colon cancer
if hadColonoscopy == false
  #The following code checks for the 'Colon Cancer' condition, and if the pateint has colon cancer, a colonoscopy encounter is created a few days before the colon cancer diagnosis as if the colon cancer was found in the colonoscopy
  $allConditions.each do |condition|
    if condition.code.text == "Colon Cancer"
      mockExtraEncounter = createEncounter()
      mockExtraEncounter.subject = {"display" => mockPatient.name[0].given[0][0].split(" ").first.chomp << " " << mockPatient.name[0].family[0][0].split(" ").first.chomp}
      extraEncounterDate = condition.dateAsserted - rand(2..4).days
      mockExtraEncounter.period = {"start" => extraEncounterDate, "end" => extraEncounterDate + rand(1..2).hours + rand(60).minutes + rand(60).seconds}
      mockExtraEncounter.identifier = [{"use" => "usual", "label" => mockPatient.name[0].given[0][0].split(" ").first.chomp << "'s colonoscopy on " << mockExtraEncounter.period.start.to_s}]
      mockExtraEncounter.reason = {text: "44388 Colonoscopy, #{mockPatient.name[0].given[0][0].split(" ").first.chomp} #{mockPatient.name[0].family[0][0].split(" ").first.chomp} came in for a colonoscopy."}
      mockExtraEncounter.serviceProvider = {"display" => "Medstar Health"}
      mockExtraEncounter.hospitalization = {"reAdmission" => true}
      hadColonoscopy = true
      if mockExtraEncounter.period.end <= Date.today
        mockExtraEncounter.status = "finished"
      else
        mockExtraEncounter.status = "in-progress"
      end
      if mockPatient.deceasedBoolean == true
        unless mockExtraEncounter.period.start > mockPatient.deceasedDateTime
          allExtraEncounters << mockExtraEncounter
        end
      else
        allExtraEncounters << mockExtraEncounter
      end
    end
  end
end

#This code iterates through allEncounters and deletes all blank encounters
allEncounters.each do |encounter|
  if encounter.reason.nil?
    allEncounters.delete(encounter)
  end
end

#This loop adds all the 'extra' encoutners that were just created to the 'allEncounters' array that is then printed to json files
allExtraEncounters.each do |extraEncounter|
  if mockPatient.deceasedBoolean == true
    if extraEncounter.period.start < mockPatient.deceasedDateTime
      allEncounters << extraEncounter
    else
      allExtraEncounters.delete(extraEncounter)
    end
  else
    allEncounters << extraEncounter
  end
end

#This code assigns each observation with an issued date
#These observations were issued during the first encounter
#'observationAssignmentDate' adds 10-14 hours to earliestEncounterDate because earliestEncounterDate is at midnight
observationAssignmentDate = earliestEncounterDate + rand(10..14).hours + rand(0..59).minutes
patientHeight.appliesPeriod = {"start" => "#{observationAssignmentDate}", "end" => "#{Date.today}"}
patientWeight.appliesPeriod = {"start" => "#{observationAssignmentDate}", "end" => "#{Date.today}"}
patientBMI.appliesPeriod = {"start" => "#{observationAssignmentDate}", "end" => "#{Date.today}"}
patientAge.appliesPeriod = {"start" => "#{observationAssignmentDate}", "end" => "#{Date.today}"}
#These observations can essentially change and/or be updated so they will be issued at any random extraEncounter (yearlyPhysical)
#If the patient has not had any yearly physicals ( maybe he/she died before her first one) then all observations are just assigned the date of the patient's first-ever encounter
if allExtraEncounters.count == 0
  patientSmokingStatus.appliesPeriod = {"start" => "#{allEncounters[0].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientDrinkingStatus.appliesPeriod = {"start" => "#{allEncounters[0].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientHDL.appliesPeriod = {"start" => "#{allEncounters[0].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientLDL.appliesPeriod = {"start" => "#{allEncounters[0].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientTriglyceride.appliesPeriod = {"start" => "#{allEncounters[0].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientFallingHistory.appliesPeriod = {"start" => "#{allEncounters[0].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientFallingRiskTest.appliesPeriod = {"start" => "#{allEncounters[0].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
else
  patientSmokingStatus.appliesPeriod = {"start" => "#{allExtraEncounters[rand(allExtraEncounters.count-1)].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientDrinkingStatus.appliesPeriod = {"start" => "#{allExtraEncounters[rand(allExtraEncounters.count-1)].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientHDL.appliesPeriod = {"start" => "#{allExtraEncounters[rand(allExtraEncounters.count-1)].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientLDL.appliesPeriod = {"start" => "#{allExtraEncounters[rand(allExtraEncounters.count-1)].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientTriglyceride.appliesPeriod = {"start" => "#{allExtraEncounters[rand(allExtraEncounters.count-1)].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientFallingHistory.appliesPeriod = {"start" => "#{allExtraEncounters[rand(allExtraEncounters.count-1)].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientFallingRiskTest.appliesPeriod = {"start" => "#{allExtraEncounters[rand(allExtraEncounters.count-1)].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}

end
#If the patient has diabetes or hypertension, the glucose and blood pressure observations will be issued the same date the diabetes and hypertension, respectively, were asserted
#I realize that if hasDiabetes and/or hasHypertension is true, then $allConditions should contain at least one condition (hypertension) but there is some bug causing an issued
#The bug is fixed by simply adding the ' && $allConditions.count > 0' because from what I've found there
if hasDiabetes == true && $allConditions.count > 0
  if hasHypertension == true && $allConditions.count > 1
    patientGlucose.appliesPeriod = {"start" => "#{$allConditions[1].dateAsserted - rand(1..2).hours + rand(30..59).minutes}", "end" => "#{Date.today}"}
  else
    patientGlucose.appliesPeriod = {"start" => "#{$allConditions[0].dateAsserted - rand(1..2).hours + rand(30..59).minutes}", "end" => "#{Date.today}"}
  end
else
  if allExtraEncounters.count == 0
    patientGlucose.appliesPeriod = {"start" => "#{allEncounters[0].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  else
    patientGlucose.appliesPeriod = {"start" => "#{allExtraEncounters[rand(allExtraEncounters.count-1)].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  end
end

#I realize that if hasDiabetes and/or hasHypertension is true, then $allConditions should contain at least one condition (hypertension) but there is some bug causing an issued
#The bug is fixed by simply adding the ' && $allConditions.count > 0' because from what I've found there
if hasHypertension == true && $allConditions.count > 0
  patientSystolicBloodPressure.appliesPeriod = {"start" => "#{$allConditions[0].dateAsserted + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  patientDiastolicBloodPressure.appliesPeriod = {"start" => "#{$allConditions[0].dateAsserted + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
else
  if allExtraEncounters.count == 0
    patientSystolicBloodPressure.appliesPeriod = {"start" => "#{allEncounters[0].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
    patientDiastolicBloodPressure.appliesPeriod = {"start" => "#{allEncounters[0].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  else
    patientSystolicBloodPressure.appliesPeriod = {"start" => "#{allExtraEncounters[rand(allExtraEncounters.count-1)].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
    patientDiastolicBloodPressure.appliesPeriod = {"start" => "#{allExtraEncounters[rand(allExtraEncounters.count-1)].period.start + rand(10..14).hours + rand(0..59).minutes}", "end" => "#{Date.today}"}
  end
end

#This line of code just ensures that the patient profile begins befoer the earliest encounter
mockPatient.identifier[0].period.start = earliestEncounterDate - rand(1..3).months - rand(0..30).days


#This code dictates whether or not the patient record is active based on if they are deceased or not
if mockPatient.deceasedBoolean == true
  mockPatient.active = false
else
  mockPatient.active = true
end

#This code does nothing with regards to the output of this script it is just a counter that can be used by the developer to see how many current conditions the patient has
numberOfCurrentConditions = 0
numberOfCuredConditions = 0
$allConditions.each do |condition|
  if condition.abatementBoolean == true
    numberOfCuredConditions += 1
  elsif condition.abatementBoolean == false
    numberOfCurrentConditions += 1
  else
    puts "Error on ~line 1310: A condition was not assigned an abatementBoolean field"
  end
end









#Writing to JSON Files####################################################################################################################################################################################################################
##########################################################################################################################################################################################################################################

#At this point in the script, all the clinical and demographic information has been set in variables and now the information will be written to JSON files in FHIR-format
#The following $postedFiles array is populated with the URL's of all resources as they are posted to the server
#This array is also used in Timeout errors where all files in $postedFiles are deleted to avoid a situation where only half of the resources are posted to the server (this way it's like an all or nothing type deal)
$postedFiles = []

#This code deletes all other files from previously generated patients that are listed in the text editor to avoid errors
fileNamesToDelete = ["Patient", "Allergy", "Age", "BMI", "DiastolicBloodPressure", "DrinkingStatus", "Glucose", "HDLCholesterol", "Height", "LDLCholesterol", "SmokingStatus", "SystolicBloodPressure", "Triglyceride", "Weight", "CauseOfDeath", "FallingHistory", "FallingRiskTest",
"Condition1", "Condition2", "Condition3", "Condition4", "Condition5", "Condition6", "Condition7", "Condition8", "Condition9", "Condition10", "Condition11", "Condition12",
"Encounter1",   "Encounter2",   "Encounter3",   "Encounter4",   "Encounter5",   "Encounter6",   "Encounter7",   "Encounter8",   "Encounter9",   "Encounter10",  "Encounter11",  "Encounter12",  "Encounter13",  "Encounter14",  "Encounter15",
"Encounter16",  "Encounter17",  "Encounter18",  "Encounter19",  "Encounter20",  "Encounter21",  "Encounter22",  "Encounter23",  "Encounter24",  "Encounter25",  "Encounter26",  "Encounter27",  "Encounter28",  "Encounter29",  "Encounter30",
"Encounter31",  "Encounter32",  "Encounter33",  "Encounter34",  "Encounter35",  "Encounter36",  "Encounter37",  "Encounter38",  "Encounter39",  "Encounter40",  "Encounter41",  "Encounter42",  "Encounter43",  "Encounter44",  "Encounter45",
"Encounter46",  "Encounter47",  "Encounter48",  "Encounter49",  "Encounter50",  "Encounter51",  "Encounter52",  "Encounter53",  "Encounter54",  "Encounter55",  "Encounter56",  "Encounter57",  "Encounter58",  "Encounter59",  "Encounter60",
"Encounter61",  "Encounter62",  "Encounter63",  "Encounter64",  "Encounter65",  "Encounter66",  "Encounter67",  "Encounter68",  "Encounter69",  "Encounter70",  "Encounter71",  "Encounter72",  "Encounter73",  "Encounter74",  "Encounter75",
"Encounter76",  "Encounter77",  "Encounter78",  "Encounter79",  "Encounter80",  "Encounter81",  "Encounter82",  "Encounter83",  "Encounter84",  "Encounter85",  "Encounter86",  "Encounter87",  "Encounter88",  "Encounter89",  "Encounter90",
"Encounter91",  "Encounter92",  "Encounter93",  "Encounter94",  "Encounter95",  "Encounter96",  "Encounter97",  "Encounter98",  "Encounter99",  "Encounter100", "Encounter101", "Encounter102", "Encounter103", "Encounter104", "Encounter105",
"Encounter106", "Encounter107", "Encounter108", "Encounter109", "Encounter110", "Encounter111", "Encounter112", "Encounter113", "Encounter114", "Encounter115", "Encounter116", "Encounter117", "Encounter118", "Encounter119", "Encounter120",
"Encounter121", "Encounter122", "Encounter123", "Encounter124", "Encounter125", "Encounter126", "Encounter127", "Encounter128", "Encounter129", "Encounter130", "Encounter131", "Encounter132", "Encounter133", "Encounter134", "Encounter135",
"Encounter136", "Encounter137", "Encounter138", "Encounter139", "Encounter140", "Encounter141", "Encounter142", "Encounter143", "Encounter144", "Encounter145", "Encounter146", "Encounter147", "Encounter148", "Encounter149", "Encounter150",
"Encounter151", "Encounter152", "Encounter153", "Encounter154", "Encounter155", "Encounter156", "Encounter157", "Encounter158", "Encounter159", "Encounter160", "Encounter161", "Encounter162", "Encounter163", "Encounter164", "Encounter165",
"Encounter166", "Encounter167", "Encounter168", "Encounter169", "Encounter170", "Encounter171", "Encounter172", "Encounter173", "Encounter174", "Encounter175", "Encounter176", "Encounter177", "Encounter178", "Encounter179", "Encounter180",
"Encounter181", "Encounter182", "Encounter183", "Encounter184", "Encounter185", "Encounter186", "Encounter187", "Encounter188", "Encounter189", "Encounter190", "Encounter191", "Encounter192", "Encounter193", "Encounter194", "Encounter195",
"Encounter196", "Encounter197", "Encounter198", "Encounter199", "Encounter200",
"Medication1", "Medication2", "Medication3", "Medication4", "Medication5", "Medication6", "Medication7", "Medication8",  "Medication9", "Medication10", "Medication11", "Medication12",
"MedicationStatement1", "MedicationStatement2", "MedicationStatement3", "MedicationStatement4", "MedicationStatement5", "MedicationStatement6", "MedicationStatement7", "MedicationStatement8", "MedicationStatement9", "MedicationStatement10", "MedicationStatement11", "MedicationStatement12",
"Procedure1", "Procedure2", "Procedure3", "Procedure4", "Procedure5", "Procedure6", "Procedure7", "Procedure8", "Procedure9", "Procedure10", "Procedure11", "Procedure12"]

fileNamesToDelete.each do |fileBaseName|
  fileNameToDeleteVar = "sample" << fileBaseName << ".json"
  if File.exist?(fileNameToDeleteVar)
    File.delete("./#{fileNameToDeleteVar}")
  end
end

#This code writes the patient profile to a json file
jsonPatient = File.open('samplePatient.json', 'w') { |patient|
  patient << "{\n"
  patient << '"resourceType": "Patient",' << "\n"
  patient << '"text": {"status": "generated"},' << "\n"
  patient << '"identifier": [{' << "\n" << '  "use": "usual",' << "\n"
  patient << '  "system": "' << mockPatient.identifier[0].system << '",' << "\n"
  patient << '  "value": "' << mockPatient.identifier[0].value << '",' << "\n"
  patient << '  "period": {'  << "\n"
  patient << '    "start": "' << mockPatient.identifier[0].period.start.to_s[0..9] << '"' << "\n"
  patient << '   },' << "\n"
  patient << '  "assigner": {'  << "\n"
  patient << '    "display": "' << mockPatient.identifier[0].assigner.display << '"' << "\n"
  patient << '   }}],' << "\n"
  patient << '"name": [{' << "\n" << '  "use": "official",' << "\n"
  patient << '  "family": ' << mockPatientLastName[0] << ',' << "\n"
  patient << '  "given": ' << mockPatientFirstName[0] << "\n" << '  }],' << "\n"
  patient << '"telecom": [' << "\n"
  patient << '  {' << "\n"
  patient << '  "system": "phone",' << "\n"
  patient << '  "value": "' << mockPatient.telecom[0].value << '",' << "\n"
  patient << '  "use": "home"' << "\n"
  patient << '  }],' << "\n"
  patient << '"gender": "' << mockPatient.gender.coding[0].display << '",' << "\n"
#  patient << '"gender": {' << "\n"
#  patient << '  "coding": [{' << "\n"
#  patient << '    "system": "http://hl7.org/fhir/v3/AdministratvieGender",' << "\n"
#  patient << '    "code": "' << mockPatient.gender.coding[0].code << '",' << "\n"
#  patient << '    "display": "' << mockPatient.gender.coding[0].display << '"}],' << "\n"
#  patient << '  "text": "' << mockPatient.gender.text << '"},' << "\n"
  patient << '"birthDate": "' << mockPatient.birthDate.to_s[0..9] << '",' << "\n"
#  patient << '"deceasedBoolean": "' << mockPatient.deceasedBoolean << '",' << "\n"
  #The previous line is compatible with the SMART on FHIR server, but the IE server only works with the following line
  patient << '"deceasedBoolean": ' << mockPatient.deceasedBoolean << ',' << "\n"
  patient << '"address": [' << "\n"
  patient << '  {' << "\n"
  patient << '    "use": "home",' << "\n"
  patient << '    "line": ["' << mockPatient.address[0].line[0] << '"],' << "\n"
  patient << '    "city": "' << mockPatient.address[0].city << '",' << "\n"
  patient << '    "state": "' << mockPatient.address[0].state << '",' << "\n"
  patient << '    "zip": "' << mockPatient.address[0].zip << '"' << "\n"
  patient << '  }' << "\n"
  patient << '],' << "\n"
  patient << '"contact": [' << "\n"
  patient << '  {' << "\n"
  patient << '    "name": {' << "\n"
  patient << '      "family": ' << mockPatient.contact[0].name.family << ',' << "\n"
  patient << '      "given": ' << mockPatient.contact[0].name.given << "\n" << '  },' << "\n"
  patient << '    "telecom": [{' << "\n"
  patient << '      "system": "phone",' << "\n"
  patient << '      "value": "' << mockPatient.contact[0].telecom[0].value << '"}]' << "\n"
  patient << '  }],' << "\n"
#  patient << '"active": "' << mockPatient.active << '"' << "\n"
  #The previous line is compatible with the SMART on FHIR server, but the IE server only works with the following line
  patient << '"active": ' << mockPatient.active << "\n"
  patient << "}\n"
  }

  #This code submits a post request for the Patient first, so the Patient ID can be extracted and used for references
  openFile = File.read("./samplePatient.json")
  #The 'rest-client' gem is used here to handle the HTTP requests
  #Notice that the authorization tag is required here to allow a post to the IE server
  patientPostVar = RestClient.post "#{serverNameInput}/Patient", openFile, :content_type => :json, :accept => :json, :Authorization => "#{authorizationTag}"
  #The following line just stores the HTTP header response to a variable
  patientIDString = patientPostVar.headers[:location]
  #The following line extracts the server-assigned patient reference ID token to a variable called '$patientIDVar'
  $patientIDVar = patientIDString[patientIDString.length-24..patientIDString.length]
# The following line may work on an external server, but it does not work on this local server that I am currently using this on
#  patientResponse = RestClient.get patientIDString.to_s
# I have implemented the following line to use with this local server
  patientResponse = RestClient.get "#{serverNameInput}/Patient/" << $patientIDVar.to_s


  $postedFiles << "#{serverNameInput}/Patient/#{$patientIDVar}"
  #This code displays to the terminal whether or not the patient was successfully created
  if (defined?($patientIDVar)).nil?
    puts "----------------------------------------------------------------------------------------------------\n"
    puts "The Patient ID was not identified in the section of the response that was searched"
  else
    puts "----------------------------------------------------------------------------------------------------\n"
    puts "The Patient ID (HTTP response code: #{patientResponse.code}) is #{$patientIDVar}"
  end

#The next ~65 lines are to post medication resources to the server
#I understand the Intervention engine doesn't use medication resource, but rather it uses only medicaion statements
#Unfortunately I did not know this while making the patient generator so the medication reources must be posted to the server for the medication Statements to be generated

#unless allMedications.count == 0
  medicationFilePrinterCounter = 0
  medicationPrinterCounter = -1
  until medicationPrinterCounter == allMedications.count-1
    medicationFilePrinterCounter += 1
    medicationPrinterCounter += 1
    if allMedications[medicationPrinterCounter].code.present?
      medicationFileNameVar = "sampleMedication" << medicationFilePrinterCounter.to_s << ".json"
      jsonMedication = File.open(medicationFileNameVar, 'w') { |medication|
        medication << "{\n"
        medication << '"resourceType": "Medication",' << "\n"
        medication << '"text": {"status": "generated"},' << "\n"
        medication << '"name": "' << allMedications[medicationPrinterCounter].name << '",' << "\n"
        medication << '"code": {' << "\n"
        medication << '  "coding": [{' << "\n"
        medication << '    "system": "http://www.nlm.nih.gov/research/umls/rxnorm/",' << "\n"
        medication << '    "code": "' << allMedications[medicationPrinterCounter].code.coding[0].code << '",' << "\n"
        medication << '    "display": "' << allMedications[medicationPrinterCounter].code.coding[0].display << '"}]},' << "\n"
        medication << '"isBrand": ' << allMedications[medicationPrinterCounter].isBrand << ',' << "\n"
        medication << '"kind": "product"' << "\n"
        medication << '}'
      }
    else
      #Sometimes a blank medications will slip through the loop  in the "#Adding Condition/Medication/Statement/Encounter to Profile Arrays" section that is supposed to delete all the blank medications created as placeholders
      #The following hack is needed to prevent these blank medications from being written to the server
      medicationFilePrinterCounter -= 1
    end
  end

  #This code submits a post request for the Medication before MedicationStatements are created, so the Medication ID can be extracted and used for in the MedicationStatement Reference
  medicationPossibleFileNames = [
    {name: "Medication1",  type: "Medication"},
    {name: "Medication2",  type: "Medication"},
    {name: "Medication3",  type: "Medication"},
    {name: "Medication4",  type: "Medication"},
    {name: "Medication5",  type: "Medication"},
    {name: "Medication6",  type: "Medication"},
    {name: "Medication7",  type: "Medication"},
    {name: "Medication8",  type: "Medication"},
    {name: "Medication9",  type: "Medication"},
    {name: "Medication10", type: "Medication"},
    {name: "Medication11", type: "Medication"},
    {name: "Medication12", type: "Medication"}
      ]

  #This code loops throught the above array and posts each json file to the server
  medicationIDsForReferences = []
  medicationPossibleFileNames.each do |fileNameBase|
    fileName = "./sample" << "#{fileNameBase[:name]}" << ".json"
    localURL = "#{serverNameInput}/" << "#{fileNameBase[:type]}"
    #Since not all generated patients will have every possible fileName, this if statement is necessary to prevent file-not-found errors
    if File.file?(fileName)
      openFile = File.read(fileName)
      medicationIteratorPostVar = RestClient.post "#{serverNameInput}/Medication", openFile, :content_type => :json, :accept => :json, :Authorization => "#{authorizationTag}"
      medicationIDString = medicationIteratorPostVar.headers[:location]
      medicationIteratorPostID = medicationIDString[medicationIDString.length-24..medicationIDString.length]
      #The following link is used for implementing a reference in medicationStatements that are also posted to the server
      medicationIDsForReferences << "#{medicationIteratorPostID}"
    # The following line may work on a real server, but it does not work on this local server that I am currently using this on
    # medicationResponse = RestClient.get medicationIDString.to_s
    #I have implemented the following line to use with this local server
      medicationResponse = RestClient.get "#{serverNameInput}/Medication/" << medicationIteratorPostID.to_s
      $postedFiles << "#{serverNameInput}/Medication/#{medicationIteratorPostID}"
      #This lines prints the name, HTTP response code, and ID value of each generated resource to the terminal
      puts "The #{fileNameBase[:type]} ID for #{fileNameBase[:name]} (HTTP response code: #{medicationResponse.code}) is #{medicationIteratorPostID}"
    end
  end

#The following code generates medicationStatement JSON files
begin
  medicationStatementFilePrinterCounter = 0
  medicationStatementPrinterCounter = -1
  until medicationStatementPrinterCounter == allMedicationStatements.count-1
    medicationStatementFilePrinterCounter += 1
    medicationStatementPrinterCounter += 1
    if allMedicationStatements[medicationStatementPrinterCounter].medication.present?
      medicationStatementFileNameVar = "sampleMedicationStatement" << medicationStatementFilePrinterCounter.to_s << ".json"
      jsonMedicationStatement = File.open(medicationStatementFileNameVar, 'w') { |medicationStatement|
        medicationStatement << "{\n"
        medicationStatement << '"resourceType": "MedicationStatement",' << "\n"
        medicationStatement << '"text": {"status": "generated"},' << "\n"
        medicationStatement << '"patient": {' << "\n"
        medicationStatement << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
        medicationStatement << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '",' << "\n"
        medicationStatement << '  "referenceid": "' << $patientIDVar << '",' << "\n"
        medicationStatement << '  "external": false},' << "\n"
        medicationStatement << '"medicationCodeableConcept": {' << "\n"
        medicationStatement << '  "coding": [{' << "\n"
        medicationStatement << '    "system": "http://www.nlm.nih.gov/research/umls/rxnorm/",' << "\n"
        medicationStatement << '    "code": "' << allMedications[medicationStatementPrinterCounter].code.coding[0].code << '"}],'
        medicationStatement << '  "text": "Medication: ' << allMedications[medicationStatementPrinterCounter].name << '"},' << "\n"
        #The following 'if/else' statment deals with the fact that some medicationStatements have an end date, while others are ongoing
        if allMedicationStatements[medicationStatementPrinterCounter].whenGiven.end.present?
          medicationStatement << '"effectivePeriod": {' << "\n"
          medicationStatement << '  "start": {"time": "' << allMedicationStatements[medicationStatementPrinterCounter].whenGiven.start.to_s[0..9] << '"},' << "\n"
          medicationStatement << '  "end": {"time": "' << allMedicationStatements[medicationStatementPrinterCounter].whenGiven.end.to_s[0..9] << '"}},' << "\n"
        else
          medicationStatement << '"effectivePeriod": {"start": {"time": "' << allMedicationStatements[medicationStatementPrinterCounter].whenGiven.start.to_s[0..9] << '"}},' << "\n"
        end
        medicationStatement << '"dosage": [{' << "\n"
        medicationStatement << '  "rate": {' << "\n"
        medicationStatement << '    "numerator": {' << "\n"
        medicationStatement << '      "value": ' << allMedicationStatements[medicationStatementPrinterCounter].dosage[0].rate.numerator.value<< ',' << "\n"
        medicationStatement << '      "units": "' << allMedicationStatements[medicationStatementPrinterCounter].dosage[0].rate.numerator.units<< '"},' << "\n"
        medicationStatement << '    "denominator": {' << "\n"
        medicationStatement << '      "value": ' << allMedicationStatements[medicationStatementPrinterCounter].dosage[0].rate.denominator.value<< ',' << "\n"
        medicationStatement << '      "units": "' << allMedicationStatements[medicationStatementPrinterCounter].dosage[0].rate.denominator.units<< '"}}}]' << "\n"
        medicationStatement << '}'
      }
      else
        medicationStatementFilePrinterCounter -= 1
      end
    end
#The following 'rescue' statement deletes blank medicationStatements
rescue
#  }
  File.delete(medicationStatementFileNameVar)
  puts "#{medicationStatementFileNameVar} was deleted because it was blank (empty)"
end

#The following 'end' closes the 'unless allMedications.count == 0' line above medications
#end

#The following code generates encounter JSON files
encounterFilePrinterCounter = 0
until encounterFilePrinterCounter == allEncounters.count
encounterFilePrinterCounter += 1
encounterPrinterCounter = encounterFilePrinterCounter - 1
encounterFileNameVar = "sampleEncounter" << encounterFilePrinterCounter.to_s << ".json"
  begin
  jsonEncounter = File.open(encounterFileNameVar, 'w') { |encounter|
    encounter << "{\n"
    encounter << '"resourceType": "Encounter",' << "\n"
    encounter << '"text": {"status": "generated"},' << "\n"
    encounter << '"patient": {' << "\n"
    encounter << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
    encounter << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"},' << "\n"
    encounter << '"status": "' << allEncounters[encounterPrinterCounter].status << '",' << "\n"
    encounter << '"type": [{' << "\n"
    encounter << '  "coding": [{' << "\n"
    encounter << '    "system": "http://www.ama-assn.org/go/cpt/",' << "\n"
    encounter << '    "code": "' << allEncounters[encounterPrinterCounter].reason.text.split(",").first[0..4] << '",' << "\n"
    encounter << '    "display": "' << allEncounters[encounterPrinterCounter].reason.text.split(",").first[6..allEncounters[encounterPrinterCounter].reason.text.split(",").first.length] << '"}]}],' << "\n"
    encounter << '"period": {' << "\n"
    encounter << '  "start": "' << allEncounters[encounterPrinterCounter].period.start.to_s[0..9] << '",' << "\n"
    encounter << '  "end": "' << allEncounters[encounterPrinterCounter].period.end.to_s[0..9] << '"},' << "\n"
    encounter << '"reason": [{"text": "' << allEncounters[encounterPrinterCounter].reason.text.split(",").last.chomp << '"}],' << "\n"
    encounter << '"hospitalization": {"reAdmission": ' << allEncounters[encounterPrinterCounter].hospitalization.reAdmission << '},' << "\n"
    encounter << '"serviceProvider": {"display": "MedStar Health"}' << "\n"
    encounter << "}"
  }
  #The following 'rescue' code was used to delete blank encounters that slipped through; I believe the bug has been fixed, but I'm going to leave this 'rescue' code just in case
  rescue
    File.delete(encounterFileNameVar)
    puts "#{encounterFileNameVar} was deleted because it was blank (empty)"
  end
end

#This code submits a post request for the Encounter before Conditions and Procedures are created, so the Encounter ID can be extracted and used for in Condition/Procedure references
#The reason there are so many here is because cancer patients have a lot of chemotherapy treatments
encounterPossibleFileNames = [
{name: "Encounter1", type: "Encounter"},
{name: "Encounter2", type: "Encounter"},
{name: "Encounter3", type: "Encounter"},
{name: "Encounter4", type: "Encounter"},
{name: "Encounter5", type: "Encounter"},
{name: "Encounter6", type: "Encounter"},
{name: "Encounter7", type: "Encounter"},
{name: "Encounter8", type: "Encounter"},
{name: "Encounter9", type: "Encounter"},
{name: "Encounter10", type: "Encounter"},
{name: "Encounter11", type: "Encounter"},
{name: "Encounter12", type: "Encounter"},
{name: "Encounter13", type: "Encounter"},
{name: "Encounter14", type: "Encounter"},
{name: "Encounter15", type: "Encounter"},
{name: "Encounter15", type: "Encounter"},
{name: "Encounter16", type: "Encounter"},
{name: "Encounter17", type: "Encounter"},
{name: "Encounter18", type: "Encounter"},
{name: "Encounter19", type: "Encounter"},
{name: "Encounter20", type: "Encounter"},
{name: "Encounter21", type: "Encounter"},
{name: "Encounter22", type: "Encounter"},
{name: "Encounter23", type: "Encounter"},
{name: "Encounter24", type: "Encounter"},
{name: "Encounter25", type: "Encounter"},
{name: "Encounter26", type: "Encounter"},
{name: "Encounter27", type: "Encounter"},
{name: "Encounter28", type: "Encounter"},
{name: "Encounter29", type: "Encounter"},
{name: "Encounter30", type: "Encounter"},
{name: "Encounter31", type: "Encounter"},
{name: "Encounter32", type: "Encounter"},
{name: "Encounter33", type: "Encounter"},
{name: "Encounter34", type: "Encounter"},
{name: "Encounter35", type: "Encounter"},
{name: "Encounter36", type: "Encounter"},
{name: "Encounter37", type: "Encounter"},
{name: "Encounter38", type: "Encounter"},
{name: "Encounter39", type: "Encounter"},
{name: "Encounter40", type: "Encounter"},
{name: "Encounter41", type: "Encounter"},
{name: "Encounter42", type: "Encounter"},
{name: "Encounter43", type: "Encounter"},
{name: "Encounter44", type: "Encounter"},
{name: "Encounter45", type: "Encounter"},
{name: "Encounter46", type: "Encounter"},
{name: "Encounter47", type: "Encounter"},
{name: "Encounter48", type: "Encounter"},
{name: "Encounter49", type: "Encounter"},
{name: "Encounter50", type: "Encounter"},
{name: "Encounter51", type: "Encounter"},
{name: "Encounter52", type: "Encounter"},
{name: "Encounter53", type: "Encounter"},
{name: "Encounter54", type: "Encounter"},
{name: "Encounter55", type: "Encounter"},
{name: "Encounter56", type: "Encounter"},
{name: "Encounter57", type: "Encounter"},
{name: "Encounter58", type: "Encounter"},
{name: "Encounter59", type: "Encounter"},
{name: "Encounter60", type: "Encounter"},
{name: "Encounter61", type: "Encounter"},
{name: "Encounter62", type: "Encounter"},
{name: "Encounter63", type: "Encounter"},
{name: "Encounter64", type: "Encounter"},
{name: "Encounter65", type: "Encounter"},
{name: "Encounter66", type: "Encounter"},
{name: "Encounter67", type: "Encounter"},
{name: "Encounter68", type: "Encounter"},
{name: "Encounter69", type: "Encounter"},
{name: "Encounter70", type: "Encounter"},
{name: "Encounter71", type: "Encounter"},
{name: "Encounter72", type: "Encounter"},
{name: "Encounter73", type: "Encounter"},
{name: "Encounter74", type: "Encounter"},
{name: "Encounter75", type: "Encounter"},
{name: "Encounter76", type: "Encounter"},
{name: "Encounter77", type: "Encounter"},
{name: "Encounter78", type: "Encounter"},
{name: "Encounter79", type: "Encounter"},
{name: "Encounter80", type: "Encounter"},
{name: "Encounter81", type: "Encounter"},
{name: "Encounter82", type: "Encounter"},
{name: "Encounter83", type: "Encounter"},
{name: "Encounter84", type: "Encounter"},
{name: "Encounter85", type: "Encounter"},
{name: "Encounter86", type: "Encounter"},
{name: "Encounter87", type: "Encounter"},
{name: "Encounter88", type: "Encounter"},
{name: "Encounter89", type: "Encounter"},
{name: "Encounter90", type: "Encounter"},
{name: "Encounter91", type: "Encounter"},
{name: "Encounter92", type: "Encounter"},
{name: "Encounter93", type: "Encounter"},
{name: "Encounter94", type: "Encounter"},
{name: "Encounter95", type: "Encounter"},
{name: "Encounter96", type: "Encounter"},
{name: "Encounter97", type: "Encounter"},
{name: "Encounter98", type: "Encounter"},
{name: "Encounter99", type: "Encounter"},
{name: "Encounter100", type: "Encounter"},
{name: "Encounter101", type: "Encounter"},
{name: "Encounter102", type: "Encounter"},
{name: "Encounter103", type: "Encounter"},
{name: "Encounter104", type: "Encounter"},
{name: "Encounter105", type: "Encounter"},
{name: "Encounter106", type: "Encounter"},
{name: "Encounter107", type: "Encounter"},
{name: "Encounter108", type: "Encounter"},
{name: "Encounter109", type: "Encounter"},
{name: "Encounter110", type: "Encounter"},
{name: "Encounter111", type: "Encounter"},
{name: "Encounter112", type: "Encounter"},
{name: "Encounter113", type: "Encounter"},
{name: "Encounter114", type: "Encounter"},
{name: "Encounter115", type: "Encounter"},
{name: "Encounter116", type: "Encounter"},
{name: "Encounter117", type: "Encounter"},
{name: "Encounter118", type: "Encounter"},
{name: "Encounter119", type: "Encounter"},
{name: "Encounter120", type: "Encounter"},
{name: "Encounter121", type: "Encounter"},
{name: "Encounter122", type: "Encounter"},
{name: "Encounter123", type: "Encounter"},
{name: "Encounter124", type: "Encounter"},
{name: "Encounter125", type: "Encounter"},
{name: "Encounter126", type: "Encounter"},
{name: "Encounter127", type: "Encounter"},
{name: "Encounter128", type: "Encounter"},
{name: "Encounter129", type: "Encounter"},
{name: "Encounter130", type: "Encounter"},
{name: "Encounter131", type: "Encounter"},
{name: "Encounter132", type: "Encounter"},
{name: "Encounter133", type: "Encounter"},
{name: "Encounter134", type: "Encounter"},
{name: "Encounter135", type: "Encounter"},
{name: "Encounter136", type: "Encounter"},
{name: "Encounter137", type: "Encounter"},
{name: "Encounter138", type: "Encounter"},
{name: "Encounter139", type: "Encounter"},
{name: "Encounter140", type: "Encounter"},
{name: "Encounter141", type: "Encounter"},
{name: "Encounter142", type: "Encounter"},
{name: "Encounter143", type: "Encounter"},
{name: "Encounter144", type: "Encounter"},
{name: "Encounter145", type: "Encounter"},
{name: "Encounter146", type: "Encounter"},
{name: "Encounter147", type: "Encounter"},
{name: "Encounter148", type: "Encounter"},
{name: "Encounter149", type: "Encounter"},
{name: "Encounter150", type: "Encounter"},
{name: "Encounter151", type: "Encounter"},
{name: "Encounter152", type: "Encounter"},
{name: "Encounter153", type: "Encounter"},
{name: "Encounter154", type: "Encounter"},
{name: "Encounter155", type: "Encounter"},
{name: "Encounter156", type: "Encounter"},
{name: "Encounter157", type: "Encounter"},
{name: "Encounter158", type: "Encounter"},
{name: "Encounter159", type: "Encounter"},
{name: "Encounter160", type: "Encounter"},
{name: "Encounter161", type: "Encounter"},
{name: "Encounter162", type: "Encounter"},
{name: "Encounter163", type: "Encounter"},
{name: "Encounter164", type: "Encounter"},
{name: "Encounter165", type: "Encounter"},
{name: "Encounter166", type: "Encounter"},
{name: "Encounter167", type: "Encounter"},
{name: "Encounter168", type: "Encounter"},
{name: "Encounter169", type: "Encounter"},
{name: "Encounter170", type: "Encounter"},
{name: "Encounter171", type: "Encounter"},
{name: "Encounter172", type: "Encounter"},
{name: "Encounter173", type: "Encounter"},
{name: "Encounter174", type: "Encounter"},
{name: "Encounter175", type: "Encounter"},
{name: "Encounter176", type: "Encounter"},
{name: "Encounter177", type: "Encounter"},
{name: "Encounter178", type: "Encounter"},
{name: "Encounter179", type: "Encounter"},
{name: "Encounter180", type: "Encounter"},
{name: "Encounter181", type: "Encounter"},
{name: "Encounter182", type: "Encounter"},
{name: "Encounter183", type: "Encounter"},
{name: "Encounter184", type: "Encounter"},
{name: "Encounter185", type: "Encounter"},
{name: "Encounter186", type: "Encounter"},
{name: "Encounter187", type: "Encounter"},
{name: "Encounter188", type: "Encounter"},
{name: "Encounter189", type: "Encounter"},
{name: "Encounter190", type: "Encounter"},
{name: "Encounter191", type: "Encounter"},
{name: "Encounter192", type: "Encounter"},
{name: "Encounter193", type: "Encounter"},
{name: "Encounter194", type: "Encounter"},
{name: "Encounter195", type: "Encounter"},
{name: "Encounter196", type: "Encounter"},
{name: "Encounter197", type: "Encounter"},
{name: "Encounter198", type: "Encounter"},
{name: "Encounter199", type: "Encounter"},
{name: "Encounter200", type: "Encounter"}
  ]

#This code loops throught the above array and posts each json file to the local SMART on FHIR server
 encounterIDsForReferences = []
 encounterPossibleFileNames.each do |fileNameBase|
  fileName = "./sample" << "#{fileNameBase[:name]}" << ".json"
  localURL = "#{serverNameInput}/" << "#{fileNameBase[:type]}"
  #Since not all generated patients will have every possible fileName, this 'if' statement is necessary to prevent file-not-found errors
  if File.file?(fileName)
    openFile = File.read(fileName)
    encounterIteratorPostVar = RestClient.post "#{serverNameInput}/Encounter", openFile, :content_type => :json, :accept => :json, :Authorization => "2O8vklDrr17txn0gyjKCC0_vQ490X-ab33PhU4prPUM="
    encounterIDString = encounterIteratorPostVar.headers[:location]
    encounterIteratorPostID = encounterIDString[encounterIDString.length-24..encounterIDString.length]
    # The following line may work on a real server, but it does not work on this local server that I am currently using this on
    #encounterResponse = RestClient.get encounterIDString.to_s
    # I have implemented the following line to use with this local server
    encounterResponse = RestClient.get "#{serverNameInput}/Encounter/" << encounterIteratorPostID.to_s
    $postedFiles << "#{serverNameInput}/Encounter/#{encounterIteratorPostID}"
    #This lines prints the name, HTTP response code, and ID value of each generated resource to the terminal
    puts "The #{fileNameBase[:type]} ID for #{fileNameBase[:name]} (HTTP response code: #{encounterResponse.code}) is #{encounterIteratorPostID}"
  end
end

#The following code generates condition JSON files
conditionFilePrinterCounter = 0
until conditionFilePrinterCounter == $allConditions.count
conditionFilePrinterCounter += 1
conditionPrinterCounter = conditionFilePrinterCounter - 1
conditionFileNameVar = "sampleCondition" << conditionFilePrinterCounter.to_s << ".json"
  jsonCondition = File.open(conditionFileNameVar, 'w') { |condition|
    condition << "{\n"
    condition << '"resourceType": "Condition",' << "\n"
    condition << '"text": {"status": "generated"},' << "\n"
    condition << '"patient": {' << "\n"
    condition << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
    condition << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"},' << "\n"
    condition << '"onsetDateTime": "' << $allConditions[conditionPrinterCounter].dateAsserted.to_s[0..9] << '",' << "\n"
    condition << '"code": {' << "\n"
    condition << '  "coding": [{' << "\n"
    condition << '    "system": "http://hl7.org/fhir/sid/icd-9",' << "\n"
    condition << '    "code": "' << $allConditions[conditionPrinterCounter].code.coding[0].code << '",' << "\n"
    condition << '    "display": "' << $allConditions[conditionPrinterCounter].code.coding[0].display << '"}],' << "\n"
    condition << '  "text": "' << $allConditions[conditionPrinterCounter].code.text << '"},'<< "\n"
    condition << '"category": {' << "\n"
    condition << '  "coding": [{' << "\n"
    condition << '    "system": "http://hl7.org/fhir/condition-category",' << "\n"
    condition << '    "code": "diagnosis",' << "\n"
    condition << '    "display": "Diagnosis"}]},' << "\n"
    #The following 'if' statement only adds an abatementDate field if the condition was indeed abated
    if $allConditions[conditionPrinterCounter].abatementBoolean == true
      jsonCondition = File.open(conditionFileNameVar, 'a') { |condition|
        condition << '"abatementDate": "' << $allConditions[conditionPrinterCounter].abatementDate << '",' << "\n" }
    end
    condition << '"clinicalStatus": "confirmed"' << "\n"
    condition << '}'
    }
end

#The following code generates procedure JSON files (if the patient underwent a procedure)
if allProcedures.count > 0
  procedureFilePrinterCounter = 0
  until procedureFilePrinterCounter == allProcedures.count
    procedureFilePrinterCounter += 1
    procedurePrinterCounter = procedureFilePrinterCounter - 1
    procedureFileNameVar = "sampleProcedure" << procedureFilePrinterCounter.to_s << ".json"
    jsonProcedure = File.open(procedureFileNameVar, 'w') { |procedure|
      procedure << "{\n"
      procedure << '"resourceType": "Procedure",' << "\n"
      procedure << '"text": {"status": "generated"},' << "\n"
      procedure << '"patient": {' << "\n"
      procedure << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
      procedure << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"},' << "\n"
      if allProcedures[procedurePrinterCounter].date.end > Date.today
        procedure << '"status": "in-progress",' << "\n"
      else
        procedure << '"status": "completed",' << "\n"
      end
      procedure << '"type": {' << "\n"
      procedure << '  "coding": [{' << "\n"
      procedure << '    "system": "http://www.ama-assn.org/go/cpt",' << "\n"
      procedure << '    "code": "' << allProcedures[procedurePrinterCounter].notes[6..10] << '",' << "\n"
      procedure << '    "display": "' << allProcedures[procedurePrinterCounter].notes[22..allProcedures[procedurePrinterCounter].notes.length] << '"}]},' << "\n"
      procedure << '"date":{' << "\n"
      procedure << '  "start": "' << allProcedures[procedurePrinterCounter].date.start << '",' << "\n"
      procedure << '  "end": "' << allProcedures[procedurePrinterCounter].date.end << '"},' << "\n"
      procedure << '"encounter": {"display": "' << allProcedures[procedurePrinterCounter].encounter.display << '"}' << "\n"
      procedure << '}'
    }
  end
end

#The following code generates an allergy JSON file if the patient was assigned an allergy
unless allergyChoice == "N/A"
  jsonAllergy = File.open('sampleAllergy.json', 'w') { |allergy|
    allergy << "{\n"
    allergy << '"resourceType": "AllergyIntolerance",' << "\n"
    allergy << '"text": {"status": "generated"},' << "\n"
    allergy << '"patient": {' << "\n"
    allergy << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
    allergy << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"},' << "\n"
    allergy << '"identifier": [{' << "\n"
    allergy << '  "label": "' << allergyName << '"}],' << "\n"
    allergy << '"substance": {' << "\n"
    allergy << '  "coding": [{' << "\n"
    allergy << '    "system": "http://snomed.info/sct",' << "\n"
    allergy << '    "code": "' << allergyCode << '",' << "\n"
    allergy << '    "display": "' << allergyName << '"}]},' << "\n"
    allergy << '"criticality": "' << mockAllergy.criticality << '",' << "\n"
    allergy << '"status": "confirmed"' << "\n"
    allergy << '}'
  }
end

#The following code generates an observation JSON file regarding the patient's smoking status
jsonSmokingStatus = File.open('sampleSmokingStatus.json', 'w') { |smokingStatus|
  smokingStatus << "{\n"
  smokingStatus << '"resourceType": "Observation",' << "\n"
  smokingStatus << '"text": {"status": "generated"},' << "\n"
  smokingStatus << '"code": {' << "\n"
  smokingStatus << '  "coding": [{' << "\n"
  smokingStatus << '    "system": "http://snomed.info/sct",' << "\n"
  smokingStatus << '    "code": "' << patientSmokingStatus.name.coding[0].code << '",' << "\n"
  smokingStatus << '    "display": "' << patientSmokingStatus.name.text << '"}],' << "\n"
  smokingStatus << '  "text": "Smoking Status"},' << "\n"
  smokingStatus << '"effectivePeriod": {' << "\n"
  smokingStatus << '  "start": "' << patientSmokingStatus.appliesPeriod.start << '",' << "\n"
  smokingStatus << '  "end": "' << patientSmokingStatus.appliesPeriod.end << '"},' << "\n"
  smokingStatus << '"subject": {' << "\n"
  smokingStatus << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  smokingStatus << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  smokingStatus << '}'
}

#The following code generates an observation JSON file regarding the patient's drinking status
jsonDrinkingStatus = File.open('sampleDrinkingStatus.json', 'w') { |drinkingStatus|
  drinkingStatus << "{\n"
  drinkingStatus << '"resourceType": "Observation",' << "\n"
  drinkingStatus << '"text": {"status": "generated"},' << "\n"
  drinkingStatus << '"code": {' << "\n"
  drinkingStatus << '  "coding": [{' << "\n"
  drinkingStatus << '    "system": "http://snomed.info/sct",' << "\n"
  drinkingStatus << '    "code": "' << patientDrinkingStatus.name.coding[0].code << '",' << "\n"
  drinkingStatus << '    "display": "' << patientDrinkingStatus.name.text << '"}],' << "\n"
  drinkingStatus << '  "text": "Drinking Status"},' << "\n"
  drinkingStatus << '"effectivePeriod": {' << "\n"
  drinkingStatus << '  "start": "' << patientDrinkingStatus.appliesPeriod.start << '",' << "\n"
  drinkingStatus << '  "end": "' << patientDrinkingStatus.appliesPeriod.end << '"},' << "\n"
  drinkingStatus << '"subject": {' << "\n"
  drinkingStatus << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  drinkingStatus << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  drinkingStatus << '}'
}

#The following code generates an observation JSON file regarding the patient's systolic blood pressure
jsonSystolicBloodPressure = File.open('sampleSystolicBloodPressure.json', 'w') { |systolicBloodPressure|
  systolicBloodPressure << "{\n"
  systolicBloodPressure << '"resourceType": "Observation",' << "\n"
  systolicBloodPressure << '"text": {"status": "generated"},' << "\n"
  systolicBloodPressure << '"code": {' << "\n"
  systolicBloodPressure << '  "coding": [{' << "\n"
  systolicBloodPressure << '    "system": "http://snomed.info/sct",' << "\n"
  systolicBloodPressure << '    "code": "' << patientSystolicBloodPressure.name.coding[0].code << '",' << "\n"
  systolicBloodPressure << '    "display": "' << patientSystolicBloodPressure.name.text << '"}]},' << "\n"
  systolicBloodPressure << '"valueQuantity": {' << "\n"
  systolicBloodPressure << '  "value": ' << patientSystolicBloodPressure.valueQuantity.value << ',' << "\n"
  systolicBloodPressure << '  "units": "' << patientSystolicBloodPressure.valueQuantity.units << '"},' << "\n"
  systolicBloodPressure << '"effectivePeriod": {' << "\n"
  systolicBloodPressure << '  "start": "' << patientSystolicBloodPressure.appliesPeriod.start << '",' << "\n"
  systolicBloodPressure << '  "end": "' << patientSystolicBloodPressure.appliesPeriod.end << '"},' << "\n"
  systolicBloodPressure << '"subject": {' << "\n"
  systolicBloodPressure << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  systolicBloodPressure << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  systolicBloodPressure << '}'
}

#The following code generates an observation JSON file regarding the patient's diastolic blood pressure
jsonDiastolicBloodPressure = File.open('sampleDiastolicBloodPressure.json', 'w') { |diastolicBloodPressure|
  diastolicBloodPressure << "{\n"
  diastolicBloodPressure << '"resourceType": "Observation",' << "\n"
  diastolicBloodPressure << '"text": {"status": "generated"},' << "\n"
  diastolicBloodPressure << '"code": {' << "\n"
  diastolicBloodPressure << '  "coding": [{' << "\n"
  diastolicBloodPressure << '    "system": "http://snomed.info/sct",' << "\n"
  diastolicBloodPressure << '    "code": "' << patientDiastolicBloodPressure.name.coding[0].code << '",' << "\n"
  diastolicBloodPressure << '    "display": "' << patientDiastolicBloodPressure.name.text << '"}]},' << "\n"
  diastolicBloodPressure << '"valueQuantity": {' << "\n"
  diastolicBloodPressure << '  "value": ' << patientDiastolicBloodPressure.valueQuantity.value << ',' << "\n"
  diastolicBloodPressure << '  "units": "' << patientDiastolicBloodPressure.valueQuantity.units << '"},' << "\n"
  diastolicBloodPressure << '"effectivePeriod": {' << "\n"
  diastolicBloodPressure << '  "start": "' << patientDiastolicBloodPressure.appliesPeriod.start << '",' << "\n"
  diastolicBloodPressure << '  "end": "' << patientDiastolicBloodPressure.appliesPeriod.end << '"},' << "\n"
  diastolicBloodPressure << '"subject": {' << "\n"
  diastolicBloodPressure << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  diastolicBloodPressure << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  diastolicBloodPressure << '}'
}

#The following code generates an observation JSON file regarding the patient's low-density-lipid cholesterol
jsonLDLCholesterol = File.open('sampleLDLCholesterol.json', 'w') { |lDLCholesterol|
  lDLCholesterol << "{\n"
  lDLCholesterol << '"resourceType": "Observation",' << "\n"
  lDLCholesterol << '"text": {"status": "generated"},' << "\n"
  lDLCholesterol << '"code": {' << "\n"
  lDLCholesterol << '  "coding": [{' << "\n"
  lDLCholesterol << '    "system": "http://snomed.info/sct",' << "\n"
  lDLCholesterol << '    "code": "' << patientLDL.name.coding[0].code << '",' << "\n"
  lDLCholesterol << '    "display": "' << patientLDL.name.text << '"}]},' << "\n"
  lDLCholesterol << '"valueQuantity": {' << "\n"
  lDLCholesterol << '  "value": ' << patientLDL.valueQuantity.value << ',' << "\n"
  lDLCholesterol << '  "units": "' << patientLDL.valueQuantity.units << '"},' << "\n"
  lDLCholesterol << '"effectivePeriod": {' << "\n"
  lDLCholesterol << '  "start": "' << patientLDL.appliesPeriod.start << '",' << "\n"
  lDLCholesterol << '  "end": "' << patientLDL.appliesPeriod.end << '"},' << "\n"
  lDLCholesterol << '"subject": {' << "\n"
  lDLCholesterol << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  lDLCholesterol << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  lDLCholesterol << '}'
}

#The following code generates an observation JSON file regarding the patient's high-density-lipid cholesterol
jsonHDLCholesterol = File.open('sampleHDLCholesterol.json', 'w') { |hDLCholesterol|
  hDLCholesterol << "{\n"
  hDLCholesterol << '"resourceType": "Observation",' << "\n"
  hDLCholesterol << '"text": {"status": "generated"},' << "\n"
  hDLCholesterol << '"code": {' << "\n"
  hDLCholesterol << '  "coding": [{' << "\n"
  hDLCholesterol << '    "system": "http://snomed.info/sct",' << "\n"
  hDLCholesterol << '    "code": "' << patientHDL.name.coding[0].code << '",' << "\n"
  hDLCholesterol << '    "display": "' << patientHDL.name.text << '"}]},' << "\n"
  hDLCholesterol << '"valueQuantity": {' << "\n"
  hDLCholesterol << '  "value": ' << patientHDL.valueQuantity.value << ',' << "\n"
  hDLCholesterol << '  "units": "' << patientHDL.valueQuantity.units << '"},' << "\n"
  hDLCholesterol << '"effectivePeriod": {' << "\n"
  hDLCholesterol << '  "start": "' << patientHDL.appliesPeriod.start << '",' << "\n"
  hDLCholesterol << '  "end": "' << patientHDL.appliesPeriod.end << '"},' << "\n"
  hDLCholesterol << '"subject": {' << "\n"
  hDLCholesterol << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  hDLCholesterol << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  hDLCholesterol << '}'
}

#The following code generates an observation JSON file regarding the patient's triglyceride levels
jsonTriglyceride = File.open('sampleTriglyceride.json', 'w') { |triglyceride|
  triglyceride << "{\n"
  triglyceride << '"resourceType": "Observation",' << "\n"
  triglyceride << '"text": {"status": "generated"},' << "\n"
  triglyceride << '"code": {' << "\n"
  triglyceride << '  "coding": [{' << "\n"
  triglyceride << '    "system": "http://snomed.info/sct",' << "\n"
  triglyceride << '    "code": "' << patientTriglyceride.name.coding[0].code << '",' << "\n"
  triglyceride << '    "display": "' << patientTriglyceride.name.text << '"}]},' << "\n"
  triglyceride << '"valueQuantity": {' << "\n"
  triglyceride << '  "value": ' << patientTriglyceride.valueQuantity.value << ',' << "\n"
  triglyceride << '  "units": "' << patientTriglyceride.valueQuantity.units << '"},' << "\n"
  triglyceride << '"effectivePeriod": {' << "\n"
  triglyceride << '  "start": "' << patientTriglyceride.appliesPeriod.start << '",' << "\n"
  triglyceride << '  "end": "' << patientTriglyceride.appliesPeriod.end << '"},' << "\n"
  triglyceride << '"subject": {' << "\n"
  triglyceride << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  triglyceride << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  triglyceride << '}'
}

#The following code generates an observation JSON file regarding the patient's age
jsonAge = File.open('sampleAge.json', 'w') { |age|
  age << "{\n"
  age << '"resourceType": "Observation",' << "\n"
  age << '"text": {"status": "generated"},' << "\n"
  age << '"code": {' << "\n"
  age << '  "coding": [{' << "\n"
  age << '    "system": "http://snomed.info/sct",' << "\n"
  age << '    "code": "' << patientAge.name.coding[0].code << '",' << "\n"
  age << '    "display": "' << patientAge.name.text << '"}]},' << "\n"
  age << '"valueQuantity": {' << "\n"
  age << '  "value": ' << patientAge.valueQuantity.value << ',' << "\n"
  age << '  "units": "' << patientAge.valueQuantity.units << '"},' << "\n"
  age << '"effectivePeriod": {' << "\n"
  age << '  "start": "' << patientAge.appliesPeriod.start << '",' << "\n"
  age << '  "end": "' << patientAge.appliesPeriod.end << '"},' << "\n"
  age << '"subject": {' << "\n"
  age << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  age << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  age << '}'
}

#The following code generates an observation JSON file regarding the patient's height
jsonHeight = File.open('sampleHeight.json', 'w') { |height|
  height << "{\n"
  height << '"resourceType": "Observation",' << "\n"
  height << '"text": {"status": "generated"},' << "\n"
  height << '"code": {' << "\n"
  height << '  "coding": [{' << "\n"
  height << '    "system": "http://snomed.info/sct",' << "\n"
  height << '    "code": "' << patientHeight.name.coding[0].code << '",' << "\n"
  height << '    "display": "' << patientHeight.name.text << '"}]},' << "\n"
  height << '"valueQuantity": {' << "\n"
  height << '  "value": ' << patientHeight.valueQuantity.value << ',' << "\n"
  height << '  "units": "' << patientHeight.valueQuantity.units << '"},' << "\n"
  height << '"effectivePeriod": {' << "\n"
  height << '  "start": "' << patientHeight.appliesPeriod.start << '",' << "\n"
  height << '  "end": "' << patientHeight.appliesPeriod.end << '"},' << "\n"
  height << '"subject": {' << "\n"
  height << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  height << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  height << '}'
}

#The following code generates an observation JSON file regarding the patient's weight
jsonWeight = File.open('sampleWeight.json', 'w') { |weight|
  weight << "{\n"
  weight << '"resourceType": "Observation",' << "\n"
  weight << '"text": {"status": "generated"},' << "\n"
  weight << '"code": {' << "\n"
  weight << '  "coding": [{' << "\n"
  weight << '    "system": "http://snomed.info/sct",' << "\n"
  weight << '    "code": "' << patientWeight.name.coding[0].code << '",' << "\n"
  weight << '    "display": "' << patientWeight.name.text << '"}]},' << "\n"
  weight << '"valueQuantity": {' << "\n"
  weight << '  "value": ' << patientWeight.valueQuantity.value << ',' << "\n"
  weight << '  "units": "' << patientWeight.valueQuantity.units << '"},' << "\n"
  weight << '"effectivePeriod": {' << "\n"
  weight << '  "start": "' << patientWeight.appliesPeriod.start << '",' << "\n"
  weight << '  "end": "' << patientWeight.appliesPeriod.end << '"},' << "\n"
  weight << '"subject": {' << "\n"
  weight << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  weight << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  weight << '}'
}

#The following code generates an observation JSON file regarding the patient's body mass index
jsonBMI = File.open('sampleBMI.json', 'w') { |bMI|
  bMI << "{\n"
  bMI << '"resourceType": "Observation",' << "\n"
  bMI << '"text": {"status": "generated"},' << "\n"
  bMI << '"code": {' << "\n"
  bMI << '  "coding": [{' << "\n"
  bMI << '    "system": "http://snomed.info/sct",' << "\n"
  bMI << '    "code": "' << patientBMI.name.coding[0].code << '",' << "\n"
  bMI << '    "display": "' << patientBMI.name.text << '"}]},' << "\n"
  bMI << '"valueQuantity": {' << "\n"
  bMI << '  "value": ' << patientBMI.valueQuantity.value << '},' << "\n"
  bMI << '"effectivePeriod": {' << "\n"
  bMI << '  "start": "' << patientBMI.appliesPeriod.start << '",' << "\n"
  bMI << '  "end": "' << patientBMI.appliesPeriod.end << '"},' << "\n"
  bMI << '"subject": {' << "\n"
  bMI << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  bMI << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  bMI << '}'
}

#The following code generates an observation JSON file regarding the patient's blood glucose levels
jsonGlucose = File.open('sampleGlucose.json', 'w') { |glucose|
  glucose << "{\n"
  glucose << '"resourceType": "Observation",' << "\n"
  glucose << '"text": {"status": "generated"},' << "\n"
  glucose << '"code": {' << "\n"
  glucose << '  "coding": [{' << "\n"
  glucose << '    "system": "http://snomed.info/sct",' << "\n"
  glucose << '    "code": "' << patientGlucose.name.coding[0].code << '",' << "\n"
  glucose << '    "display": "' << patientGlucose.name.text << '"}]},' << "\n"
  glucose << '"valueQuantity": {' << "\n"
  glucose << '  "value": ' << patientGlucose.valueQuantity.value << ',' << "\n"
  glucose << '  "units": "' << patientGlucose.valueQuantity.units << '"},' << "\n"
  glucose << '"effectivePeriod": {' << "\n"
  glucose << '  "start": "' << patientGlucose.appliesPeriod.start << '",' << "\n"
  glucose << '  "end": "' << patientGlucose.appliesPeriod.end << '"},' << "\n"
  glucose << '"subject": {' << "\n"
  glucose << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  glucose << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  glucose << '}'
}


#The following code generates an observation JSON file regarding the patient's falling history
jsonFallingHistory = File.open('sampleFallingHistory.json', 'w') { |fallingHistory|
  fallingHistory << "{\n"
  fallingHistory << '"resourceType": "Observation",' << "\n"
  fallingHistory << '"text": {"status": "generated"},' << "\n"
  fallingHistory << '"code": {' << "\n"
  fallingHistory << '  "coding": [{' << "\n"
  fallingHistory << '    "system": "http://snomed.info/sct",' << "\n"
  fallingHistory << '    "code": "' << patientFallingHistory.name.coding[0].code << '",' << "\n"
  fallingHistory << '    "display": "' << patientFallingHistory.name.text << '"}]},' << "\n"
  fallingHistory << '"effectivePeriod": {' << "\n"
  fallingHistory << '  "start": "' << patientFallingHistory.appliesPeriod.start << '",' << "\n"
  fallingHistory << '  "end": "' << patientFallingHistory.appliesPeriod.end << '"},' << "\n"
  fallingHistory << '"subject": {' << "\n"
  fallingHistory << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  fallingHistory << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  fallingHistory << '}'
}

#The following code generates an observation JSON file regarding the patient's falling risk test
jsonFallingRiskTest = File.open('sampleFallingRiskTest.json', 'w') { |fallingRiskTest|
  fallingRiskTest << "{\n"
  fallingRiskTest << '"resourceType": "Observation",' << "\n"
  fallingRiskTest << '"text": {"status": "generated"},' << "\n"
  fallingRiskTest << '"code": {' << "\n"
  fallingRiskTest << '  "coding": [{' << "\n"
  fallingRiskTest << '    "system": "http://snomed.info/sct",' << "\n"
  fallingRiskTest << '    "code": "' << patientFallingRiskTest.name.coding[0].code << '",' << "\n"
  fallingRiskTest << '    "display": "' << patientFallingRiskTest.name.text << '"}]},' << "\n"
  fallingRiskTest << '"effectivePeriod": {' << "\n"
  fallingRiskTest << '  "start": "' << patientFallingRiskTest.appliesPeriod.start << '",' << "\n"
  fallingRiskTest << '  "end": "' << patientFallingRiskTest.appliesPeriod.end << '"},' << "\n"
  fallingRiskTest << '"subject": {' << "\n"
  fallingRiskTest << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
  fallingRiskTest << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
  fallingRiskTest << '}'
}

#The following code generates an observation JSON file regarding the patient's death (only if the patient is deceased)
if mockPatient.deceasedBoolean == true
  jsonCauseOfDeath = File.open('sampleCauseOfDeath.json', 'w') { |causeOfDeath|
    causeOfDeath << "{\n"
    causeOfDeath << '"resourceType": "Observation",' << "\n"
    causeOfDeath << '"text": {"status": "generated"},' << "\n"
    causeOfDeath << '"code": {' << "\n"
    causeOfDeath << '  "coding": [{' << "\n"
    causeOfDeath << '    "system": "http://snomed.info/sct",' << "\n"
    causeOfDeath << '    "code": "419099009",' << "\n"
    causeOfDeath << '    "display": "Death (Due to ' << $causeOfDeathVar << ')"}],' << "\n"
    causeOfDeath << '  "text": "Patient Died from ' << $causeOfDeathVar << '"},' << "\n"
    causeOfDeath << '"effectivePeriod": {' << "\n"
    causeOfDeath << '  "start": "' << mockPatient.deceasedDateTime.to_datetime << '",' << "\n"
    causeOfDeath << '  "end": "' << Date.today << '"},' << "\n"
    causeOfDeath << '"subject": {' << "\n"
    causeOfDeath << '  "reference": "Patient/' << "#{$patientIDVar}" << '",' << "\n"
    causeOfDeath << '  "display": "' << mockPatientFirstName[0][0] << ' ' << mockPatientLastName[0][0] << '"}' << "\n"
    causeOfDeath << '}'
  }
end







#HTTP Post Requests####################################################################################################################################################################################################################################
####################################################################################################################################################################################################################################

#This array will later be iterated to post every generated resource to the server
#Patient, Medications, and Encounters are not included in this array because they are posted before the rest, so their IDs can be used for references
possibleFileNames = [
                     {name: "Allergy",                type: "AllergyIntolerance"},
                     {name: "Age",                    type: "Observation"},
                     {name: "Height",                 type: "Observation"},
                     {name: "Weight",                 type: "Observation"},
                     {name: "BMI",                    type: "Observation"},
                     {name: "DrinkingStatus",         type: "Observation"},
                     {name: "SmokingStatus",          type: "Observation"},
                     {name: "SystolicBloodPressure",  type: "Observation"},
                     {name: "DiastolicBloodPressure", type: "Observation"},
                     {name: "HDLCholesterol",         type: "Observation"},
                     {name: "LDLCholesterol",         type: "Observation"},
                     {name: "Triglyceride",           type: "Observation"},
                     {name: "Glucose",                type: "Observation"},
                     {name: "FallingHistory",         type: "Observation"},
                     {name: "FallingRiskTest",        type: "Observation"},
                     {name: "CauseOfDeath",           type: "Observation"},
                     {name: "Condition1",             type: "Condition"},
                     {name: "Condition2",             type: "Condition"},
                     {name: "Condition3",             type: "Condition"},
                     {name: "Condition4",             type: "Condition"},
                     {name: "Condition5",             type: "Condition"},
                     {name: "Condition6",             type: "Condition"},
                     {name: "Condition7",             type: "Condition"},
                     {name: "Condition8",             type: "Condition"},
                     {name: "Condition9",             type: "Condition"},
                     {name: "Condition10",            type: "Condition"},
                     {name: "Condition11",            type: "Condition"},
                     {name: "Condition12",            type: "Condition"},
                     {name: "MedicationStatement1",   type: "MedicationStatement"},
                     {name: "MedicationStatement2",   type: "MedicationStatement"},
                     {name: "MedicationStatement3",   type: "MedicationStatement"},
                     {name: "MedicationStatement4",   type: "MedicationStatement"},
                     {name: "MedicationStatement5",   type: "MedicationStatement"},
                     {name: "MedicationStatement6",   type: "MedicationStatement"},
                     {name: "MedicationStatement7",   type: "MedicationStatement"},
                     {name: "MedicationStatement8",   type: "MedicationStatement"},
                     {name: "MedicationStatement9",   type: "MedicationStatement"},
                     {name: "MedicationStatement10",  type: "MedicationStatement"},
                     {name: "MedicationStatement11",  type: "MedicationStatement"},
                     {name: "MedicationStatement12",  type: "MedicationStatement"},
                     {name: "Procedure1",             type: "Procedure"},
                     {name: "Procedure2",             type: "Procedure"},
                     {name: "Procedure3",             type: "Procedure"},
                     {name: "Procedure4",             type: "Procedure"},
                     {name: "Procedure5",             type: "Procedure"},
                     {name: "Procedure6",             type: "Procedure"},
                     {name: "Procedure7",             type: "Procedure"},
                     {name: "Procedure8",             type: "Procedure"},
                     {name: "Procedure9",             type: "Procedure"},
                     {name: "Procedure10",            type: "Procedure"},
                     {name: "Procedure11",            type: "Procedure"},
                     {name: "Procedure12",            type: "Procedure"}
                    ]

#This code loops throught the above array and posts each json file to the server
possibleFileNames.each do |fileNameBase|
  fileName = "./sample" << "#{fileNameBase[:name]}" << ".json"
  localURL = "#{serverNameInput}/" << "#{fileNameBase[:type]}"
  #Since not all generated patients will have every possible fileName, this if statement is necessary to prevent file-not-found errors
  if File.file?(fileName)
    openFile = File.read(fileName)
    resourceIteratorPostVar = RestClient.post localURL, openFile, :content_type => :json, :accept => :json, :Authorization => "#{authorizationTag}"
    resourceIDString = resourceIteratorPostVar.headers[:location]
    resourceIteratorPostID = resourceIDString[resourceIDString.length-24..resourceIDString.length]
    # The following line may work on a real server, but it does not work on this local server that I am currently using this on
    # medicationResponse = RestClient.get medicationIDString.to_s
    #I have implemented the following line to use with this local server
    resourceResponse = RestClient.get "#{serverNameInput}/#{fileNameBase[:type]}/#{resourceIteratorPostID}"
    #This lines prints the name, HTTP response code, and ID value of each generated resource to the terminal
    puts "The #{fileNameBase[:type]} ID for #{fileNameBase[:name]} (HTTP response code: #{resourceResponse.code}) is #{resourceIteratorPostID}"
    $postedFiles << "#{serverNameInput}/#{fileNameBase[:type]}/#{resourceIteratorPostID}"
  end
end
puts "----------------------------------------------------------------------------------------------------\n"


#This closes the 'Timeout' loop
end

#The following code was used to implement a timeout error/rescue but so far it has been unecessary and has only caused problems to I am commenting it out for now
##This code prevents the script from getting stuck (sometimes it just loads forever with no output)
##This code just exits the script and deletes all resources that were posted before to the server before it got stuck (so there are not like half-patients on the server)
#rescue Timeout::Error
#  if defined?($postedFiles)
#    if $postedFiles.present?
#      $postedFiles.each do |postedFile|
#        begin
#          RestClient.delete "#{postedFile}"
#          puts "#{postedFile} was deleted after the timeout error occured\n"
#        rescue
#          puts "#{postedFile} was not found so it couldn't be deleted"
#        end
#      end
#    else
#      puts "There was a timeout error, but no files were posted to the server\n"
#    end
#  end
#end

#The following bit opens binding.pry if there is an error anywhere in the loop
rescue Exception => e
  puts "AN ERROR OCCURRED: #{e}"
  puts e.backtrace
  #The following line was to open binding.pry for testing purposes
  #binding.pry
  raise e
end

#The following 'end' closes the loop that creates a single patient and all its supporting resources (this loop is likely run several times to create several patients)
end
