module AbrStateMethods::GA
  
  PDF_FIELDS = {
    "First": {
      method: "first_name"
    },
     "Middle": {
      method: "middle_name"
    },
    "Last": {
      method: "last_name"
    },
    "Suffix": {
      method: "name_suffix"
    },
    "Permanent Street Address": {
      method: "address"
    },
    "Permanent City": {
      method: "city"
    },
    "Permanent Zip": {
      method: "zip"
    },
    "Permanent County": {}, #residence county
    #"Text13": {}, #mailing street
    "Temporary Street Address": {},
    #"Text14": {}, #mailing city
    "Temporary City": {}, 
    #"Text15": {}, #mailing zip
    "Temporary Zip": {},
    "Temporary State": {}, #New?
    #"Text16": {}, #mailing county
    "Temporary County": {},
    
    #"Text17": {
    "Date of Birth": {
        method: "date_of_birth_mm_dd_yyyy"
    },
      #"Text18": {
    "Phone number": {
        method: "phone"
    },
      #"Text19": {
    "Email": {
        method: "email"
    },
  
    "Name of assistant": {},

    #"Text25": {}, #requestor's relationship to voter
    "Relationship to voter": {},

    #"Text26": {
    "Email required for UOCAVA voters requesting electronic transmission": {
      method: "email_if_uocava" #only required if "Elegibility_U" is checked
    },

    "Election_Date": {
      value: "11/3/2020"
    },
    #"type_of_ballot": {
    "Group1": {
      options: ["Democratic", "Republican", "Non_Partisan"]
    },
    #"reason_other": {
    "Group2": {
      options:  [ "physically disabled", "temporarily residing out of the country"]
    },
    "D  Disabled  I have a physical disability": { 
      options: ["Off", "On"],
      method: "check_Elegibility_D",
     },
    "E  Elderly  I am 65 years of age or older": { 
      options: ["Off", "On"],  
      method: "check_Elegibility_E", },
    "U  UOCAVA Voter    I am a uniformed service member spouse or dependent of a uniformed": { 
      options: ["Off", "On"],
      method: "check_Elegibility_U",
     },

    #"UOCAVA_Status": {
    "Group3": {
      options: ["MOS", "MST", "OSP", "OST"]
    },
    #"Text21": {}, #today's date
    #"Text23": {}, #today's date assistant
    #voter_signature
    
  }
 
  EXTRA_FIELDS = ["has_mailing_address", "assisted_voter", "requestor", "request_electronic_transmission", "Elegibility"] 
  
  def form_field_items
    [
      {"Permanent County": {type: :select, required: true, include_blank: true, options: [
        "Appling",
        "Atkinson",
        "Bacon",
        "Baker",
        "Baldwin",
        "Banks",
        "Barrow",
        "Bartow",
        "Ben Hill",
        "Berrien",
        "Bibb",
        "Bleckley",
        "Brantley",
        "Brooks",
        "Bryan",
        "Bulloch",
        "Burke",
        "Butts",
        "Calhoun",
        "Camden",
        "Candler",
        "Carroll",
        "Catoosa",
        "Charlton",
        "Chatham",
        "Chattahoochee",
        "Chattooga",
        "Cherokee",
        "Clarke",
        "Clay",
        "Clayton",
        "Clinch",
        "Cobb",
        "Coffee",
        "Colquitt",
        "Columbia",
        "Cook",
        "Coweta",
        "Crawford",
        "Crisp",
        "Dade",
        "Dawson",
        "De Kalb",
        "Decatur",
        "Dodge",
        "Dooly",
        "Dougherty",
        "Douglas",
        "Early",
        "Echols",
        "Effingham",
        "Elbert",
        "Emanuel",
        "Evans",
        "Fannin",
        "Fayette",
        "Floyd",
        "Forsyth",
        "Franklin",
        "Fulton",
        "Gilmer",
        "Glascock",
        "Glynn",
        "Gordon",
        "Grady",
        "Greene",
        "Gwinnett",
        "Habersham",
        "Hall",
        "Hancock",
        "Haralson",
        "Harris",
        "Hart",
        "Heard",
        "Henry",
        "Houston",
        "Irwin",
        "Jackson",
        "Jasper",
        "Jeff Davis",
        "Jefferson",
        "Jenkins",
        "Johnson",
        "Jones",
        "Lamar",
        "Lanier",
        "Laurens",
        "Lee",
        "Liberty",
        "Lincoln",
        "Long",
        "Lowndes",
        "Lumpkin",
        "Macon",
        "Madison",
        "Marion",
        "McDuffie",
        "McIntosh",
        "Meriwether",
        "Miller",
        "Mitchell",
        "Monroe",
        "Montgomery",
        "Morgan",
        "Murray",
        "Muscogee",
        "Newton",
        "Oconee",
        "Oglethorpe",
        "Paulding",
        "Peach",
        "Pickens",
        "Pierce",
        "Pike",
        "Polk",
        "Pulaski",
        "Putnam",
        "Quitman",
        "Rabun",
        "Randolph",
        "Richmond",
        "Rockdale",
        "Schley",
        "Screven",
        "Seminole",
        "Spalding",
        "Stephens",
        "Stewart",
        "Sumter",
        "Talbot",
        "Taliaferro",
        "Tattnall",
        "Taylor",
        "Telfair",
        "Terrell",
        "Thomas",
        "Tift",
        "Toombs",
        "Towns",
        "Treutlen",
        "Troup",
        "Turner",
        "Twiggs",
        "Union",
        "Upson",
        "Walker",
        "Walton",
        "Ware",
        "Warren",
        "Washington",
        "Wayne",
        "Webster",
        "Wheeler",
        "White",
        "Whitfield",
        "Wilcox",
        "Wilkes",
        "Wilkinson",
        "Worth",
      ]}},
      #{"type_of_ballot": {type: :radio, required: true }}, 
      {"Group1": {type: :radio, required: true }}, 
      {"has_mailing_address": {type: :checkbox}},


      {"Temporary Street Address": {visible: "has_mailing_address", required: 'star'}},
      {"Temporary City": {visible: "has_mailing_address", required: 'star'}},
      {"Temporary State": {visible: "has_mailing_address", classes: "half",  type: :select, options: GeoState.collection_for_select, include_blank: true, required: 'star' }},
      {"Temporary Zip": {visible: "has_mailing_address", classes: "half", required:'star', min: 5, max: 10}},
      {"Temporary County": {visible: "has_mailing_address", required:'star'}},

    
      {"assisted_voter": {type: :checkbox}},
      {"Name of assistant": {visible: "assisted_voter", required: "star"}},

      {"requestor": {type: :checkbox}},

      {"Relationship to voter": {visible: "requestor", required: 'star'}},
      
      {"Group2": {visible: "requestor", type: :radio, required: 'star'}},
     
     
      {"Elegibility": {
        type: :radio,
        options: ["D", "E", "U"]
      }},
      #{"UOCAVA_Status": {visible: "Elegibility_u", type: :radio, }},
      {"Group3": {visible: "Elegibility_u", type: :radio, }},
      {"request_electronic_transmission": {visible: "Elegibility_u", type: :checkbox, }},

    ]
  end
  #e.g.
  # [
  #   {"Security Number": {required: true}},
  #   {"State": {visible: "has_mailing_address", type: :select, options: GeoState.collection_for_select, include_blank: true, }},
  #   {"ZIP_2": {visible: "has_mailing_address", min: 5, max: 10}},
  #   {"identification": {
  #     type: :radio,
  #     required: true,
  #     options: ["dln", "ssn4", "photoid"]}},
  #   {"OR": {visible: "identification_dln", min: 8, max: 8, regexp: /\A[a-zA-Z]{2}\d{6}\z/}},
  #   {"OR_2": {visible: "identification_ssn4", min: 4, max: 4, regexp: /\A\d{4}\z/}},
  # ]
  
    MAIL_FIELDS=[    
      "Temporary Street Address",
      "Temporary City", 
      "Temporary Zip",
      "Temporary State",
      "Temporary County",
    ]
  
  def custom_form_field_validations
    if self.has_mailing_address.to_s == "1"
      MAIL_FIELDS.each do |f|
        custom_validates_presence_of(f)
       end
    end
    if self.requestor.to_s == "1"
      custom_validates_presence_of("Relationship to voter")
      custom_validates_presence_of("Group2")
    end
    if self.assisted_voter.to_s == "1"
      custom_validates_presence_of("Name of assistant")
    end
    if self.Elegibility == "U"
      custom_validates_presence_of("Group3")
    end
  end
  



  def email_if_uocava
    self.Elegibility == "U" && self.request_electronic_transmission == "1" ? email : nil
  end


  def check_Elegibility (x)
    return (self.Elegibility==x ? "On" : "Off")
  end

  #These should be closures

  def check_Elegibility_D
    check_Elegibility("D")
  end
  def check_Elegibility_E
    check_Elegibility("E")
  end
  def check_Elegibility_U
    check_Elegibility("U")
  end 


end