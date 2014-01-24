# encoding: utf-8

#***** BEGIN LICENSE BLOCK *****
#
#Version: RTV Public License 1.0
#
#The contents of this file are subject to the RTV Public License Version 1.0 (the
#"License"); you may not use this file except in compliance with the License. You
#may obtain a copy of the License at: http://www.osdv.org/license12b/
#
#Software distributed under the License is distributed on an "AS IS" basis,
#WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the
#specific language governing rights and limitations under the License.
#
#The Original Code is the Online Voter Registration Assistant and Partner Portal.
#
#The Initial Developer of the Original Code is Rock The Vote. Portions created by
#RockTheVote are Copyright (C) RockTheVote. All Rights Reserved. The Original
#Code contains portions Copyright [2008] Open Source Digital Voting Foundation,
#and such portions are licensed to you under this license by Rock the Vote under
#permission of Open Source Digital Voting Foundation.  All Rights Reserved.
#
#Contributor(s): Open Source Digital Voting Foundation, RockTheVote,
#                Pivotal Labs, Oregon State University Open Source Lab.
#
#***** END LICENSE BLOCK *****
class Registrant < ActiveRecord::Base

  class AbandonedRecord < StandardError
    attr_reader :registrant
    def initialize(registrant)
      @registrant = registrant
    end
  end

  include AASM
  include Lolrus
  include Rails.application.routes.url_helpers
  

  STEPS = [:initial, :step_1, :step_2, :step_3, :step_4, :step_5, :complete]
  
  TITLE_KEYS = I18n.t('txt.registration.titles', :locale => :en).keys
  SUFFIX_KEYS = I18n.t('txt.registration.suffixes', :locale => :en).keys
  RACE_KEYS = I18n.t('txt.registration.races', :locale => :en).keys
  PHONE_TYPE_KEYS = I18n.t('txt.registration.phone_types', :locale => :en).keys

  TITLES = RockyConf.enabled_locales.collect{|l| TITLE_KEYS.collect{|key| I18n.t("txt.registration.titles.#{key}", :locale => l) } }.flatten
  SUFFIXES = RockyConf.enabled_locales.collect{|l| SUFFIX_KEYS.collect{|key| I18n.t("txt.registration.suffixes.#{key}", :locale => l) } }.flatten
  REMINDER_EMAILS_TO_SEND = 2
  STALE_TIMEOUT = 30.minutes
  REMINDER_EMAIL_PRIORITY = 0
  WRAP_UP_PRIORITY = REMINDER_EMAIL_PRIORITY + 1


  PDF_FIELDS = [
      "home_zip_code",
       "first_name", 
       "middle_name", 
       "last_name", 
       "home_address", 
       "home_unit", 
       "home_city", 
       "mailing_address", 
       "mailing_unit", 
       "mailing_city", 
       "mailing_zip_code", 
       "prev_first_name", 
       "prev_middle_name", 
       "prev_last_name", 
       "prev_address", 
       "prev_unit", 
       "prev_city", 
       "prev_zip_code"
    ]
  
  # OVR_REGEX = /^(\p{Latin}|\P{Letter})*$/
  OVR_REGEX = /^[a-zA-Z0-9\s\+\.\-!@#\$%\^&\*_=\(\)\[\]\{\};':"\\\/,<>\?\|]*$/
  #white space and hyphen for names; and for addresses phone#s and other stuff, also include special chars such as # ( ) / + 
  PDF_FIELDS.each do |pdf_field|
    validates pdf_field, format: { with: OVR_REGEX , 
      message: :invalid_for_pdf }#I18n.t('activerecord.errors.messages.invalid_for_pdf')}
  end

  FINISH_IFRAME_URL = "https://s3.rockthevote.com/rocky/rtv-ovr-share.php"

  CSV_HEADER = [
    "Status",
    "Tracking Source",
    "Tracking ID",
    "Language",
    "Date of birth",
    "Email address",
    "First registration?",
    "US citizen?",
    "Salutation",
    "First name",
    "Middle name",
    "Last name",
    "Name suffix",
    "Home address",
    "Home unit",
    "Home city",
    "Home state",
    "Home zip code",
    "Has mailing address?",
    "Mailing address",
    "Mailing unit",
    "Mailing city",
    "Mailing state",
    "Mailing zip code",
    "Party",
    "Race",
    "Phone",
    "Phone type",
    "Opt-in to RTV email?",
    "Opt-in to RTV sms?",
    "Opt-in to Partner email?",
    "Opt-in to Partner sms?",
    "Survey question 1",
    "Survey answer 1",
    "Survey question 2",
    "Survey answer 2",
    "Volunteer for RTV",
    "Volunteer for partner",
    "Ineligible reason",
    "Started registration",
    "Finish with State",
    "Built via API"
  ]

  attr_protected :status

  aasm_column :status
  aasm_initial_state :initial
  aasm_state :initial
  aasm_state :step_1
  aasm_state :step_2, :enter => :generate_barcode
  aasm_state :step_3
  aasm_state :step_4
  aasm_state :step_5
  aasm_state :complete, :enter => :complete_registration
  aasm_state :under_18
  aasm_state :rejected

  belongs_to :partner
  belongs_to :home_state,    :class_name => "GeoState"
  belongs_to :mailing_state, :class_name => "GeoState"
  belongs_to :prev_state,    :class_name => "GeoState"

  delegate :requires_race?, :requires_party?, :to => :home_state, :allow_nil => true

  def self.validates_zip_code(*attr_names)
    configuration = { }
    configuration.update(attr_names.extract_options!)

    validates_presence_of(attr_names, configuration)
    validates_format_of(attr_names, configuration.merge(:with => /^\d{5}(-\d{4})?$/, :allow_blank => true));

    validates_each(attr_names, configuration) do |record, attr_name, value|
      if record.errors[attr_name].nil? && !GeoState.valid_zip_code?(record.send(attr_name))
        record.errors.add(attr_name, :invalid_zip, :default => configuration[:message], :value => value)
      end
    end
  end

  before_validation :clear_superfluous_fields
  before_validation :reformat_state_id_number
  before_validation :reformat_phone
  before_validation :set_opt_in_email

  after_validation :calculate_age
  after_validation :set_official_party_name
  after_validation :check_ineligible
  after_validation :enqueue_tell_friends_emails

  before_create :generate_uid

  before_save :set_questions, :set_finish_with_state

  with_options :if => :at_least_step_1? do |reg|
    reg.validates_presence_of   :partner_id
    reg.validates_inclusion_of  :has_state_license, :in=>[true,false], :unless=>[:building_via_api_call]
    reg.validates_inclusion_of  :will_be_18_by_election, :in=>[true,false], :unless=>[:building_via_api_call]
    
    reg.validates_inclusion_of  :locale, :in => RockyConf.enabled_locales
    reg.validates_presence_of   :email_address, :unless=>:not_require_email_address?
    reg.validates_format_of     :email_address, :with => Authlogic::Regex.email, :allow_blank => true
    reg.validates_zip_code      :home_zip_code
    reg.validates_presence_of   :home_state_id
    reg.validate                :validate_date_of_birth
    reg.validates_inclusion_of  :us_citizen, :in => [ false, true ], :unless => :building_via_api_call
  end

  with_options :if => :at_least_step_2? do |reg|
    reg.validates_presence_of   :name_title
    reg.validates_inclusion_of  :name_title, :in => TITLES, :allow_blank => true
    reg.validates_presence_of   :first_name, :unless => :building_via_api_call
    reg.validates_presence_of   :last_name
    reg.validates_inclusion_of  :name_suffix, :in => SUFFIXES, :allow_blank => true
    reg.validate                :validate_race_at_least_step_2,   :unless => [ :finish_with_state?, :custom_step_2? ]
    reg.validates_presence_of   :home_address,    :unless => [ :finish_with_state?, :custom_step_2? ]
    reg.validates_presence_of   :home_city,       :unless => [ :finish_with_state?, :custom_step_2? ]
    reg.validate                :validate_party_at_least_step_2,  :unless => [ :building_via_api_call, :custom_step_2? ]
    
    reg.validates_format_of :phone, :with => /[ [:punct:]]*\d{3}[ [:punct:]]*\d{3}[ [:punct:]]*\d{4}\D*/, :allow_blank => true
    reg.validates_presence_of :phone_type, :if => :has_phone?
    
  end
  

  with_options :if=> [:at_least_step_2?, :custom_step_2?] do |reg|
    reg.validates_format_of :phone, :with => /[ [:punct:]]*\d{3}[ [:punct:]]*\d{3}[ [:punct:]]*\d{4}\D*/, :allow_blank => true
    reg.validates_presence_of :phone_type, :if => :has_phone?
    reg.validate :validate_phone_present_if_opt_in_sms_at_least_step_2
  end

  with_options :if => :needs_mailing_address? do |reg|
    reg.validates_presence_of :mailing_address
    reg.validates_presence_of :mailing_city
    reg.validates_presence_of :mailing_state_id
    reg.validates_zip_code    :mailing_zip_code
  end

  with_options :if => :at_least_step_3? do |reg|
    reg.validates_presence_of :state_id_number, :unless=>:complete?
    reg.validates_format_of :state_id_number, :with => /^(none|\d{4}|[-*A-Z0-9]{7,42})$/i, :allow_blank => true
    reg.validate :validate_phone_present_if_opt_in_sms_at_least_step_3
  end
  
  with_options :if => [:at_least_step_2?, :use_short_form?] do |reg|
    reg.validates_presence_of :state_id_number, :unless=>:complete?
    reg.validates_format_of :state_id_number, :with => /^(none|\d{4}|[-*A-Z0-9]{7,42})$/i, :allow_blank => true
    reg.validates_format_of :phone, :with => /[ [:punct:]]*\d{3}[ [:punct:]]*\d{3}[ [:punct:]]*\d{4}\D*/, :allow_blank => true
    reg.validates_presence_of :phone_type, :if => :has_phone?
    reg.validate :validate_phone_present_if_opt_in_sms_use_short_form
  end

  with_options :if=>[:at_least_step_3?, :custom_step_2?] do |reg|
    reg.validates_presence_of :home_address
    reg.validates_presence_of :home_city
    reg.validate :validate_race_at_least_step_3
    reg.validate :validate_party_at_least_step_3, :unless => [:building_via_api_call]
  end

  with_options :if => :needs_prev_name? do |reg|
    reg.validates_presence_of :prev_name_title
    reg.validates_presence_of :prev_first_name
    reg.validates_presence_of :prev_last_name
  end
  with_options :if => :needs_prev_address? do |reg|
    reg.validates_presence_of :prev_address
    reg.validates_presence_of :prev_city
    reg.validates_presence_of :prev_state_id
    reg.validates_zip_code    :prev_zip_code
  end

  with_options :if => :at_least_step_5? do |reg|
    reg.validates_acceptance_of :attest_true
  end

  attr_accessor :telling_friends
  with_options :if => :telling_friends do |reg|
    reg.validates_presence_of :tell_from
    reg.validates_presence_of :tell_email
    reg.validates_format_of :tell_email, :with => Authlogic::Regex.email
    reg.validates_presence_of :tell_recipients
    reg.validates_presence_of :tell_subject
    reg.validates_presence_of :tell_message
  end

  with_options :if => :building_via_api_call do |reg|
    reg.validates_inclusion_of :opt_in_email,                      :in => [ true, false ]
    reg.validates_inclusion_of :opt_in_sms,                        :in => [ true, false ]
    reg.validates_inclusion_of :us_citizen,                        :in => [ true ], :message=>"Required value is '1' or 'true'"
  end

  validates_presence_of  :send_confirmation_reminder_emails, :in => [ true, false ], :if=>[:building_via_api_call, :finish_with_state?]


  def collect_email_address?
    collect_email_address.to_s.downcase.strip != 'no'
  end
  
  def not_require_email_address?
    !require_email_address?
  end
  
  def require_email_address?
    #!%w(no optional)
    !%w(no).include?(collect_email_address.to_s.downcase.strip)
  end

  def needs_mailing_address?
    at_least_step_2? && has_mailing_address?
  end

  def needs_prev_name?
    (at_least_step_2? || (at_least_step_2? && use_short_form?)) && change_of_name?
  end

  def needs_prev_address?
    (at_least_step_2? || (at_least_step_2? && use_short_form?)) && change_of_address?
  end

  aasm_event :save_or_reject do
    transitions :to => :rejected, :from => Registrant::STEPS, :guard => :ineligible?
    [:step_1, :step_2, :step_3, :step_4, :step_5].each do |step|
      transitions :to => step, :from => step
    end
  end

  aasm_event :advance_to_step_1 do
    transitions :to => :step_1, :from => [:initial, :step_1, :step_2, :step_3, :step_4, :rejected]
  end

  aasm_event :advance_to_step_2 do
    transitions :to => :step_2, :from => [:step_1, :step_2, :step_3, :step_4, :rejected]
  end

  aasm_event :advance_to_step_3 do
    transitions :to => :step_3, :from => [:step_2, :step_3, :step_4, :rejected]
  end

  aasm_event :advance_to_step_4 do
    transitions :to => :step_4, :from => [:step_3, :step_4, :rejected]
  end

  aasm_event :advance_to_step_5 do
    transitions :to => :step_5, :from => [:step_4, :rejected]
  end

  aasm_event :complete do
    transitions :to => :complete, :from => [:step_5]
  end

  aasm_event :request_reminder do
    transitions :to => :under_18, :from => [:rejected, :step_1]
  end

  # Builds the record from the API data and sets the correct state
  def self.build_from_api_data(data, api_finish_with_state = false)
    r = Registrant.new(data)
    r.building_via_api_call   = true
    r.finish_with_state       = api_finish_with_state
    r.status                  = api_finish_with_state ? :step_2 : :step_5
    r
  end

  def self.find_by_param(param)
    reg = find_by_uid(param)
    raise AbandonedRecord.new(reg) if reg && reg.abandoned?
    reg
  end

  def self.find_by_param!(param)
    find_by_param(param) || begin raise ActiveRecord::RecordNotFound end
  end

  def self.abandon_stale_records
    self.find_each(:batch_size=>500, :conditions => ["(abandoned != ?) AND (status != 'complete') AND (updated_at < ?)", true, STALE_TIMEOUT.seconds.ago]) do |reg|
      if reg.finish_with_state?
        reg.status = "complete"
        begin
          reg.deliver_thank_you_for_state_online_registration_email
        rescue
        end
      end
      reg.abandon!
      Rails.logger.info "Registrant #{reg.id} abandoned at #{Time.now}"
    end
  end

  ### instance methods
  attr_accessor :attest_true

  def to_param
    uid
  end

  def localization
    home_state_id && locale ?
        StateLocalization.where({:state_id  => home_state_id, :locale => locale}).first : nil
  end
  
  def en_localization
    home_state_id ? StateLocalization.where({:state_id  => home_state_id, :locale => 'en'}).first : nil
      
  end

  def at_least_step_1?
    at_least_step?(1)
  end

  def at_least_step_2?
    at_least_step?(2)
  end

  def at_least_step_3?
    at_least_step?(3)
  end

  def at_least_step_5?
    at_least_step?(5)
  end

  def clear_superfluous_fields
    unless has_mailing_address?
      self.mailing_address = nil
      self.mailing_unit = nil
      self.mailing_city = nil
      self.mailing_state = nil
      self.mailing_zip_code = nil
    end
    unless change_of_name?
      self.prev_name_title = nil
      self.prev_first_name = nil
      self.prev_middle_name = nil
      self.prev_last_name = nil
      self.prev_name_suffix = nil
    end
    unless change_of_address?
      self.prev_address = nil
      self.prev_unit = nil
      self.prev_city = nil
      self.prev_state = nil
      self.prev_zip_code = nil
    end
    # self.race = nil unless requires_race?
    self.party = nil unless requires_party?
  end

  def reformat_state_id_number
    self.state_id_number.upcase! if self.state_id_number.present? && self.state_id_number_changed?
  end

  def reformat_phone
    if phone.present? && phone_changed?
      digits = phone.gsub(/\D/,'')
      if digits.length == 10
        self.phone = [digits[0..2], digits[3..5], digits[6..9]].join('-')
      end
    end
  end
  
  def set_opt_in_email
    if !require_email_address? && email_address.blank?
      self.opt_in_email = false
    end
    return true
  end

  def validate_phone_present_if_opt_in_sms_at_least_step_2
    validate_phone_present_if_opt_in_sms
  end
  def validate_phone_present_if_opt_in_sms_at_least_step_3
    validate_phone_present_if_opt_in_sms
  end
  def validate_phone_present_if_opt_in_sms_use_short_form
    validate_phone_present_if_opt_in_sms
  end

  def validate_phone_present_if_opt_in_sms
    if (self.opt_in_sms? || self.partner_opt_in_sms?) && phone.blank?
      errors.add(:phone, :required_if_opt_in)
    end
  end

  def date_of_birth=(string_value)
    dob = nil
    if string_value.is_a?(String)
      if matches = string_value.match(/^(\d{1,2})\D+(\d{1,2})\D+(\d{4})$/)
        m,d,y = matches.captures
        dob = Date.civil(y.to_i, m.to_i, d.to_i) rescue string_value
      elsif matches = string_value.match(/^(\d{4})\D+(\d{1,2})\D+(\d{1,2})$/)
        y,m,d = matches.captures
        dob = Date.civil(y.to_i, m.to_i, d.to_i) rescue string_value
      else
        dob = string_value
      end
    else
      dob = string_value
    end
    write_attribute(:date_of_birth, dob)
  end

  def validate_date_of_birth
    return if date_of_birth_before_type_cast.is_a?(Date) || date_of_birth_before_type_cast.is_a?(Time)
    if date_of_birth_before_type_cast.blank?
      errors.add(:date_of_birth, :blank)
    else
      @raw_date_of_birth = date_of_birth_before_type_cast
      date = nil
      if matches = date_of_birth_before_type_cast.to_s.match(/^(\d{1,2})\D+(\d{1,2})\D+(\d{4})$/)
        m,d,y = matches.captures
        date = Date.civil(y.to_i, m.to_i, d.to_i) rescue nil
      elsif matches = date_of_birth_before_type_cast.to_s.match(/^(\d{4})\D+(\d{1,2})\D+(\d{1,2})$/)
        y,m,d = matches.captures
        date = Date.civil(y.to_i, m.to_i, d.to_i) rescue nil
      end
      if date
        @raw_date_of_birth = nil
        self[:date_of_birth] = date
      else
        errors.add(:date_of_birth, :format)
      end
    end
  end

  def calculate_age
    if errors[:date_of_birth].empty? && !date_of_birth.blank?
      now = (created_at || Time.now).to_date
      years = now.year - date_of_birth.year
      if (date_of_birth.month > now.month) || (date_of_birth.month == now.month && date_of_birth.day > now.day)
        years -= 1
      end
      self.age = years
    else
      self.age = nil
    end
  end
  
  def titles
    TITLE_KEYS.collect {|key| I18n.t("txt.registration.titles.#{key}", :locale=>locale)}
  end

  def suffixes
    SUFFIX_KEYS.collect {|key| I18n.t("txt.registration.suffixes.#{key}", :locale=>locale)}
  end

  def races
    RACE_KEYS.collect {|key| I18n.t("txt.registration.races.#{key}", :locale=>locale)}
  end
  
  def phone_types
    PHONE_TYPE_KEYS.collect {|key| I18n.t("txt.registration.phone_types.#{key}", :locale=>locale)}
  end

  def name_title_key
    key_for_attribute(:name_title, 'titles')
  end
  def english_name_title
    english_attribute_value(name_title_key, 'titles')
  end
  
  def name_suffix_key
    key_for_attribute(:name_suffix, 'suffixes')
  end
  def english_name_suffix
    english_attribute_value(name_suffix_key, 'suffixes')
  end
    
  def prev_name_title_key
    key_for_attribute(:prev_name_title, 'titles')
  end
  def english_prev_name_title
    english_attribute_value(prev_name_title_key, 'titles')
  end

  def prev_name_suffix_key
    key_for_attribute(:prev_name_suffix, 'suffixes')
  end
  def english_prev_name_suffix
    english_attribute_value(prev_name_suffix_key, 'suffixes')
  end
  
  def key_for_attribute(attr_name, i18n_list)
    key_value = I18n.t("txt.registration.#{i18n_list}", :locale=>locale).detect{|k,v| v==self.send(attr_name)}
    key_value && key_value.length == 2 ? key_value[0] : nil    
  end
  
  def english_attribute_value(key, i18n_list)
    key.nil? ? nil : I18n.t("txt.registration.#{i18n_list}.#{key}", :locale=>:en)
  end
  
  def self.english_races
    I18n.t('txt.registration.races', :locale=>:en).values
  end
  def english_races
    self.class.english_races
  end

  def self.english_race(locale, race)
    if locale.to_s == 'en' || english_races.include?(race)
      return race
    else
      if (race_idx = I18n.t('txt.registration.races', :locale=>locale).values.index(race))
        return I18n.t('txt.registration.races', :locale=>:en).values[race_idx]
      else
        return nil
      end
    end
  end
  
  def english_race
    self.class.english_race(locale, race)
  end
  
  def validate_race_at_least_step_2
    validate_race
  end
  def validate_race_at_least_step_3
    validate_race
  end
  
  def validate_race
    if requires_race?
      if race.blank?
        errors.add(:race, :blank)
      else
        errors.add(:race, :inclusion) unless english_races.include?(english_race)
      end
    end
  end

  def state_parties
    if requires_party?
      localization ? localization.parties + [ localization.no_party ] : []
    else
      nil
    end
  end
  
  def set_official_party_name
    return unless self.step_5? || self.complete?
    self.official_party_name = detect_official_party_name
  end
  
  
  def detect_official_party_name
    if party.blank?
      I18n.t('states.no_party_label.none')
    else
      return party if en_localization[:parties].include?(party)
      if locale.to_s == "en"
        return party == en_localization.no_party ? I18n.t('states.no_party_label.none') : party
      else
        if party == localization.no_party
          return I18n.t('states.no_party_label.none')
        else
          if (p_index = localization[:parties].index(party))
            return en_localization[:parties][p_index]
          else
            Rails.logger.warn "***** UNKNOWN PARTY:: registrant: #{id}, locale: #{locale}, party: #{party}"
            return nil
          end
        end
      end
    end
  end
  
  def english_state_parties
    if requires_party?
      en_localization ? en_localization.parties + [ en_localization.no_party ] : []
    else
      nil
    end    
  end

  
  def english_party_name
    if locale.to_s == 'en' || english_state_parties.include?(party)
      return party
    else
      if (p_idx = state_parties.index(party))
        return english_state_parties[p_idx]
      else
        return nil
      end
    end
  end

  def pdf_date_of_birth_month
    pdf_date_of_birth.split('/')[0]
  end
  def pdf_date_of_birth_day
    pdf_date_of_birth.split('/')[1]
  end
  def pdf_date_of_birth_year
    pdf_date_of_birth.split('/')[2]
  end
  
  def pdf_date_of_birth
    (date_of_birth.is_a?(Date) || date_of_birth.is_a?(DateTime)) ? date_of_birth.to_s(:month_day_year) : date_of_birth.to_s
  end

  def pdf_english_race
    if requires_race? && race != I18n.t('txt.registration.races', :locale=>locale).values.last
      english_race
    else
      ""
    end
  end
  
  def pdf_race
    if requires_race? && race != I18n.t('txt.registration.races', :locale=>locale).values.last
      race
    else
      ""
    end
  end

  def pdf_barcode
    user_code = id.to_s(36).rjust(6, "0")
    "*#{RockyConf.sponsor.barcode_prefix}-#{user_code}*".upcase
  end

  def state_id_tooltip
    localization.id_number_tooltip
  end

  def race_tooltip
    localization.race_tooltip
  end

  def party_tooltip
    localization.party_tooltip
  end

  def home_state_not_participating_text
    localization.not_participating_tooltip
  end
  
  def registration_deadline
    localization.registration_deadline
  end
  
  [:pdf_instructions, :email_instructions].each do |state_data|
    define_method("home_state_#{state_data}") do
      localization.send(state_data)
    end
  end
  
  def registration_instructions_url
    RockyConf.pdf.nvra.page1.other_block.instructions_url.gsub(
      "<LOCALE>",locale
    ).gsub("<STATE>",home_state_abbrev)
  end

  def under_18_instructions_for_home_state
    I18n.t('txt.registration.instructions.under_18',
            :state_name => home_state.name,
            :state_rule => localization.sub_18).html_safe
  end

  def validate_party_at_least_step_2
    validate_party
  end
  def validate_party_at_least_step_3
    validate_party
  end

  def validate_party
    if requires_party?
      if party.blank?
        errors.add(:party, :blank)
      else
        errors.add(:party, :inclusion) unless english_state_parties.include?(english_party_name)
      end
    end
  end

  def abandon!
    self.attributes = {:abandoned => true, :state_id_number => nil}
    self.save(:validate=>false)
  end

  # def advance_to!(next_step, new_attributes = {})
  #   self.attributes = new_attributes
  #   current_status_number = STEPS.index(aasm_current_state)
  #   next_status_number = STEPS.index(next_step)
  #   status_number = [current_status_number, next_status_number].max
  #   send("advance_to_#{STEPS[status_number]}!")
  # end

  def home_zip_code=(zip)
    self[:home_zip_code] = zip
    self.home_state = nil
    self.home_state_id = zip && (s = GeoState.for_zip_code(zip.strip)) ? s.id : self.home_state_id
  end

  def home_state_name
    home_state && home_state.name
  end
  def home_state_abbrev
    home_state && home_state.abbreviation
  end
  
  def home_state_online_reg_url
    home_state && home_state.online_reg_url(self)
  end

  def mailing_state_abbrev=(abbrev)
    self.mailing_state = GeoState[abbrev]
  end

  def mailing_state_abbrev
    mailing_state && mailing_state.abbreviation
  end

  def prev_state_abbrev=(abbrev)
    self.prev_state = GeoState[abbrev]
  end

  def prev_state_abbrev
    prev_state && prev_state.abbreviation
  end

  def home_state_online_reg_enabled?
    !home_state.nil? && home_state.online_reg_enabled?(locale)
  end
  
  def in_ovr_flow?
    has_state_license && home_state_allows_ovr?
  end
  
  def home_state_allows_ovr?
    localization ? localization.allows_ovr? : false
  end

  def custom_step_2?
    !javascript_disabled &&
      !home_state.nil? &&
      home_state_online_reg_enabled? &&
      File.exists?(File.join(Rails.root, 'app/views/step2/', "_#{custom_step_2_partial}.html.erb"))
  end


  def custom_step_2_partial
    "#{home_state.abbreviation.downcase}"
  end
  
  def has_home_state_online_registration_instructions?
    File.exists?(File.join(Rails.root, 'app/views/state_online_registrations/', "_#{home_state_online_registration_instructions_partial}.html.erb"))
  end
  
  def home_state_online_registration_instructions_partial
    "#{home_state.abbreviation.downcase}_instructions"
  end

  def has_home_state_online_registration_view?
    File.exists?(File.join(Rails.root, 'app/views/state_online_registrations/', "#{home_state_online_registration_view}.html.erb"))
  end
  
  def home_state_online_registration_view
    "#{home_state.abbreviation.downcase}"
  end

  def use_short_form?
    short_form? && !custom_step_2?
  end
    
    

  def will_be_18_by_election?
    true
  end

  def full_name
    [name_title, first_name, middle_name, last_name, name_suffix].compact.join(" ")
  end

  def prev_full_name
    [prev_name_title, prev_first_name, prev_middle_name, prev_last_name, prev_name_suffix].compact.join(" ")
  end

  def phone_and_type
    if phone.blank?
      I18n.t('txt.registration.not_given')
    else
      "#{phone} (#{phone_type})"
    end
  end

  def form_date_of_birth
    if @raw_date_of_birth
      @raw_date_of_birth
    elsif date_of_birth
      "%d-%d-%d" % [date_of_birth.month, date_of_birth.mday, date_of_birth.year]
    else
      nil
    end
  end

  def wrap_up
    complete!
  end

  def complete_registration
    I18n.locale = self.locale.to_sym
    generate_pdf
    redact_sensitive_data
    deliver_confirmation_email
    enqueue_reminder_emails
  end

  # Enqueues final registration actions for API calls
  def enqueue_complete_registration_via_api
    self.complete_registration_via_api
  end

  # Called from the worker queue to generate PDFs on the 'util' server
  def complete_registration_via_api
    generate_pdf unless self.finish_with_state?

    redact_sensitive_data

    if self.send_confirmation_reminder_emails?
      deliver_confirmation_email
      enqueue_reminder_emails
    end

    self.status = 'complete'
    self.save
  end

  def generate_barcode
    self.barcode = self.pdf_barcode
  end

  def generate_pdf!
    generate_pdf(true)
  end

  def generate_pdf(force_write = false)
    return false if self.locale.nil? || self.home_state.nil?
    prev_locale = I18n.locale
    I18n.locale = self.locale
    renderer = PdfRenderer.new(self)
    pdf = WickedPdf.new.pdf_from_string(
      renderer.render_to_string(
        'registrants/registrant_pdf', 
        :layout => 'layouts/nvra',
        :encoding => 'utf8',
        :locale=>self.locale
      ),
      :disable_internal_links         => false,
      :disable_external_links         => false,
      :encoding => 'utf8',
      :locale=>self.locale
    )
    path = pdf_file_path
    if !File.exists?(path) || force_write
      FileUtils.mkdir_p(pdf_file_dir)
      File.open(path, "w") do |f|
        f << pdf.force_encoding('UTF-8')
      end
    end
    I18n.locale = prev_locale
    self.pdf_ready = true
  end
  
  def lang
    locale
  end
  
  def to_finish_with_state_array
    [{:status               => self.extended_status,
    :create_time          => self.created_at.to_s,
    :complete_time        => self.completed_at.to_s,
    :lang                 => self.locale,
    :first_reg            => self.first_registration?,
    :home_zip_code        => self.home_zip_code,
    :us_citizen           => self.us_citizen?,
    :name_title           => self.name_title,
    :first_name           => self.first_name,
    :middle_name          => self.middle_name,
    :last_name            => self.last_name,
    :name_suffix          => self.name_suffix,
    :home_address         => self.home_address,
    :home_unit            => self.home_unit,
    :home_city            => self.home_city,
    :home_state_id        => self.home_state_id,
    :has_mailing_address  => self.has_mailing_address,
    :mailing_address      => self.mailing_address,
    :mailing_unit         => self.mailing_unit,
    :mailing_city         => self.mailing_city,
    :mailing_state_id     => self.mailing_state_id,
    :mailing_zip_code     => self.mailing_zip_code,
    :race                 => self.race,
    :party                => self.party,
    :phone                => self.phone,
    :phone_type           => self.phone_type,
    :email_address        => self.email_address,
    :source_tracking_id   => self.tracking_source,
    :partner_tracking_id  => self.tracking_id}]
  end
  
  def send_emails?
    !email_address.blank? && collect_email_address?
  end

  def deliver_confirmation_email
    if send_emails?
      Notifier.confirmation(self).deliver
    end
  end

  def deliver_thank_you_for_state_online_registration_email
    if send_emails?
      Notifier.thank_you_external(self).deliver
    end
  end

  def enqueue_reminder_emails
    if send_emails?
      self.reminders_left = REMINDER_EMAILS_TO_SEND
      enqueue_reminder_email
    else
      self.reminders_left = 0
    end
  end

  def enqueue_reminder_email
    action = Delayed::PerformableMethod.new(self, :deliver_reminder_email, [ ])
    interval = reminders_left == 2 ? AppConfig.hours_before_first_reminder : AppConfig.hours_between_first_and_second_reminder
    Delayed::Job.enqueue(action, {:priority=>REMINDER_EMAIL_PRIORITY, :run_at=>interval.from_now})
  end

  def deliver_reminder_email
    if reminders_left > 0 && send_emails?
      Notifier.reminder(self).deliver
      self.reminders_left = reminders_left - 1
      self.save(validate: false)
      enqueue_reminder_email if reminders_left > 0
    end
  rescue StandardError => error
    Airbrake.notify(
      :error_class => error.class.name,
      :error_message => "DelayedJob Worker Error(#{error.class.name}): #{error.message}",
      :request => { :params => {:worker => "deliver_reminder_email", :registrant_id => self.id} })
  end

  def redact_sensitive_data
    self.state_id_number = nil
  end


  def pdf_path(pdfpre = nil, file=false)
    "/#{file ? pdf_file_dir(pdfpre) : pdf_dir(pdfpre)}/#{to_param}.pdf"
  end
  
  def pdf_file_dir(pdfpre = nil)
    pdf_dir(pdfpre, false)
  end
  
  def pdf_dir(pdfpre = nil, url_format=true)
    if pdfpre
      "#{pdfpre}/#{bucket_code}"
    else
      if File.exists?(pdf_file_path("pdf"))
        "pdf/#{bucket_code}"
      else
        "#{url_format ? '' : "public/"}pdfs/#{bucket_code}"
      end
    end
  end

  def pdf_file_path(pdfpre = nil)
    dir = File.join(Rails.root, pdf_file_dir(pdfpre))
    File.join(Rails.root, pdf_path(pdfpre, true))
  end

  def bucket_code
    super(self.created_at)
  end

  def check_ineligible
    self.ineligible_non_participating_state = home_state && !home_state.participating?
    self.ineligible_age = age && age < 18
    self.ineligible_non_citizen = !us_citizen?
    true # don't halt save in after_validation
  end

  def ineligible?
    ineligible_non_participating_state || (ineligible_age && !under_18_ok) || ineligible_non_citizen
  end

  def eligible?
    !ineligible?
  end

  def rtv_and_partner_name
    if partner && !partner.primary?
      I18n.t('txt.rtv_and_partner', :partner_name=>partner.organization)
    else
      "Rock the Vote"
    end
  end

  def finish_iframe_url
    base_url = FINISH_IFRAME_URL
    if self.partner && !self.partner.primary? && self.partner.whitelabeled? && !self.partner.finish_iframe_url.blank?
      base_url = self.partner.finish_iframe_url
    end
    url = "#{base_url}?locale=#{self.locale}&email=#{self.email_address}"
    url += "&partner_id=#{self.partner.id}" if !self.partner.nil?
    url += "&source=#{self.tracking_source}" if !self.tracking_source.blank?
    url += "&tracking=#{self.tracking_id}" if !self.tracking_id.blank?
    url
  end

  def email_address_to_send_from
    if partner && !partner.primary? && partner.whitelabeled? && !partner.from_email.blank?
      partner.from_email
    else
      RockyConf.from_address
    end
  end

  def survey_question_1
    original_survey_question_1.blank? ? partner_survey_question_1 : original_survey_question_1
  end

  def survey_question_2
    original_survey_question_2.blank? ? partner_survey_question_2 : original_survey_question_2
  end

  def to_csv_array
    [
      status.humanize,
      self.tracking_source,
      self.tracking_id,
      locale == 'en' ? "English" : "Spanish",
      pdf_date_of_birth,
      email_address,
      yes_no(first_registration?),
      yes_no(us_citizen?),
      name_title,
      first_name,
      middle_name,
      last_name,
      name_suffix,
      home_address,
      home_unit,
      home_city,
      home_state && home_state.abbreviation,
      home_zip_code,
      yes_no(has_mailing_address?),
      mailing_address,
      mailing_unit,
      mailing_city,
      mailing_state_abbrev,
      mailing_zip_code,
      party,
      race,
      phone,
      phone_type,
      yes_no(opt_in_email?),
      yes_no(opt_in_sms?),
      yes_no(partner_opt_in_email?),
      yes_no(partner_opt_in_sms?),
      survey_question_1,
      survey_answer_1,
      survey_question_2,
      survey_answer_2,
      yes_no(volunteer?),
      yes_no(partner_volunteer?),
      ineligible_reason,
      created_at && created_at.to_s(:month_day_year),
      yes_no(finish_with_state?),
      yes_no(building_via_api_call?)
    ]
  end

  def status_text
    I18n.locale = self.locale.to_sym
    @status_text ||=
      CGI.escape(
        case self.status.to_sym
        when :complete, :step_5 ; I18n.t('txt.status_text.message')
        when :under_18 ; I18n.t('txt.status_text.under_18_message')
        else ""
        end
        )
  end

  ### tell-a-friend email

  attr_writer :tell_from, :tell_email, :tell_recipients, :tell_subject, :tell_message
  attr_accessor :tell_recipients, :tell_message

  def tell_from
    @tell_from ||= "#{first_name} #{last_name}"
  end

  def tell_email
    @tell_email ||= send_emails? ? email_address : email_address_to_send_from
  end

  def tell_subject
    @tell_subject ||=
      case self.status.to_sym
      when :complete ; I18n.t('email.tell_friend.subject')
      when :under_18 ; I18n.t('email.tell_friend_under_18.subject')
      end
  end

  def enqueue_tell_friends_emails
    if @telling_friends && self.errors.blank?
        tell_params = {
          :tell_from       => self.tell_from,
          :tell_email      => self.tell_email,
          :tell_recipients => self.tell_recipients,
          :tell_subject    => self.tell_subject,
          :tell_message    => self.tell_message
        }
      self.class.send_later(:deliver_tell_friends_emails, tell_params)
    end
  end

  def self.deliver_tell_friends_emails(tell_params)
    # disabled until spammers can be stopped
    #tell_params[:tell_recipients].split(",").each do |recipient|
    #  Notifier.deliver_tell_friends(tell_params.merge(:tell_recipients => recipient))
    #end
  end

  def self.backfill_data
    counter = 0
    self.find_each do |r|
      r.calculate_age
      r.set_official_party_name
      r.generate_barcode
      r.save(:validate=>false)
      unless Rails.env.test?
        putc "." if (counter += 1) % 1000 == 0; $stdout.flush
      end
    end
    puts " done!" unless Rails.env.test?
  end

  def completed_at
    complete? && updated_at || nil
  end

  def extended_status
    if complete?
      'complete'
    elsif /step/ =~ status.to_s
      "abandoned after #{status}".gsub('_', ' ')
    else
      'abandoned'
    end
  end

  private ###

  def at_least_step?(step)
    current_step = STEPS.index(aasm_current_state)
    !current_step.nil? && (current_step >= step)
  end

  def has_phone?
    !phone.blank?
  end

  def generate_uid
    self.uid = Digest::SHA1.hexdigest( "#{Time.now.usec} -- #{rand(1000000)} -- #{email_address} -- #{home_zip_code}" )
  end

  def yes_no(attribute)
    attribute ? "Yes" : "No"
  end
  
  def method_missing(sym, *args)
    if sym.to_s =~ /^yes_no_(.+)$/
      attribute = $1
      return self.send(:yes_no, (self.send(attribute)))
    else
      super
    end
  end
  
  def ineligible_reason
    case
    when ineligible_non_citizen? then "Not a US citizen"
    when ineligible_non_participating_state? then "State doesn't participate"
    when ineligible_age? then "Not old enough to register"
    else nil
    end
  end

  def partner_survey_question_1
    partner.send("survey_question_1_#{locale}")
  end

  def partner_survey_question_2
    partner.send("survey_question_2_#{locale}")
  end

  def set_questions
    if self.survey_answer_1_changed? && !self.original_survey_question_1_changed?
      self.original_survey_question_1 = partner_survey_question_1
    end
    if self.survey_answer_2_changed? && !self.original_survey_question_2_changed?
      self.original_survey_question_2 = partner_survey_question_2
    end
    true
  end
  
  def set_finish_with_state
    self.finish_with_state = false unless self.home_state_online_reg_enabled?
    return true
  end
end
