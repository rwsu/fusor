import Ember from 'ember';

export default Ember.ObjectController.extend({
  needs: ['application'],

  identification: null,
  password: null,
  errorMessage: null,

});
