import Ember from 'ember';

export default Ember.Controller.extend({
  needs: ['application', 'rhev-setup', 'side-menu', 'deployment', 'storage', 'rhev-options'],

  rhevSetup: Ember.computed.alias("controllers.rhev-setup.rhevSetup"),

  isSelfHost: function() {
    return (this.get('rhevSetup') === 'selfhost');
  }.property('rhevSetup'),

  engineTabName: function() {
    if (this.get('isSelfHost')) {
      return 'Engine/Hypervisor';
    } else {
      return 'Engine';
    }
  }.property('isSelfHost'),

  disableTabRhevSetupType: false,
  disableTabRhevEngine: false,

  hasEngine: function() {
    return !!(this.get('controllers.deployment.discovered_host.id'));
  }.property('controllers.deployment.discovered_host.id'),
  hasNoEngine: Ember.computed.not('hasEngine'),

  hasHypervisor: function() {
    return (this.get('controllers.deployment.discovered_hosts.length') > 0);
  }.property('controllers.deployment.discovered_hosts.[]'),
  hasNoHypervisor: Ember.computed.not('hasHypervisor'),

  disableTabRhevHypervisors: function() {
    return (!this.get('controllers.deployment.rhev_is_self_hosted') && this.get('hasNoEngine'));
  }.property('controllers.deployment.rhev_is_self_hosted', 'hasNoEngine'),

  disableTabRhevConfiguration: function() {
    return ((this.get('controllers.deployment.rhev_is_self_hosted') && this.get('hasNoEngine')) ||
            (!this.get('controllers.deployment.rhev_is_self_hosted') && this.get('hasNoHypervisor'))
           );
  }.property('controllers.deployment.rhev_is_self_hosted', 'hasNoEngine', 'hasNoHypervisor'),

  disableTabRhevStorage: function () {
    return (Ember.isBlank(this.get('controllers.deployment.rhev_root_password')) ||
            Ember.isBlank(this.get('controllers.deployment.rhev_engine_admin_password')) ||
            (this.get('controllers.deployment.rhev_root_password.length') < 8) ||
            (this.get('controllers.deployment.rhev_engine_admin_password.length') < 8)
           );
  }.property('controllers.deployment.rhev_root_password', 'controllers.deployment.rhev_engine_admin_password'),

  validRhevSetup: true,
  validRhevEngine: Ember.computed.alias("hasEngine"),
  validRhevHypervisor: Ember.computed.not("disableTabRhevConfiguration"),
  validRhevOptions: Ember.computed.alias("controllers.rhev-options.validRhevOptions"),
  validRhevStorage: Ember.computed.alias("controllers.storage.validRhevStorage"),

  validRhev: function() {
    return this.get('validRhevSetup') && this.get('validRhevEngine') && this.get('validRhevHypervisor') &&
           this.get('validRhevOptions') && this.get('validRhevStorage');
  }.property('validRhevSetup', 'validRhevEngine', 'validRhevHypervisor', 'validRhevOptions', 'validRhevStorage'),
});
