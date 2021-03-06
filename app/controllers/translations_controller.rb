# Copyright 2014 Square Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

# Controller for working with Translations. The `TranslationWorkbench` JavaScript
# uses these endpoints to modify, approve, and reject Translations.

class TranslationsController < ApplicationController
  include TranslationDecoration

  before_filter :translator_required, only: [:edit, :update]
  before_filter :reviewer_required, only: [:show_in_search, :hide_in_search]

  before_filter :find_project
  before_filter :find_key
  before_filter :find_translation
  before_filter :find_issues, only: [:show, :edit, :hide_in_search, :show_in_search]

  respond_to :html, except: [:match, :fuzzy_match]
  respond_to :json, only: [:show, :match, :fuzzy_match]

  # Displays a large-format translation view page.
  #
  # Routes
  # ------
  #
  # * `PATCH /projects/:project_id/keys/:key_id/translations/:id`
  #
  # Path Parameters
  # ---------------
  #
  # |              |                                    |
  # |:-------------|:-----------------------------------|
  # | `project_id` | The slug of a Project.             |
  # | `key_id`     | The slug of a Key in that project. |
  # | `id`         | The ID of a Translation.           |

  def show
    respond_with(@translation, location: project_key_translation_url(@project, @key, @translation)) do |format|
      format.json { render json: decorate([@translation]).first }
    end
  end

  # Displays a large-format translation edit page.
  #
  # Routes
  # ------
  #
  # * `GET /projects/:project_id/keys/:key_id/translations/:id/edit`
  #
  # Path Parameters
  # ---------------
  #
  # |              |                                    |
  # |:-------------|:-----------------------------------|
  # | `project_id` | The slug of a Project.             |
  # | `key_id`     | The slug of a Key in that project. |
  # | `id`         | The ID of a Translation.           |

  def edit
    @params = params

    # reasons logic
    @reasons = Reason.order(:category)
    @reason_badges = []
    @severity_badge = nil
    severity_texts = TranslationChange.reason_severities.map {|s| s[0].titlecase}

    changes = @translation.translation_changes.to_a
    changes.sort! { |x,y| y <=> x }

    @reason_badges = changes.map do |change|
      change.reasons.map do |reason|
        { id: reason.id, text: "#{reason.category}: #{reason.name}"}
      end
    end

    @reason_badges.flatten!

    latest_severity = changes.find {|c| c.reason_severity }
    severity = latest_severity&.reason_severity

    if severity
      @severity_badge = {
        class_name: TranslationChange::SEVERITY_CLASSES[severity],
        severity: severity,
        severity_text: "Severity: #{severity_texts[severity]}"
      }
    end

    respond_with(@translation, location: project_key_translation_url(@project, @key, @translation)) do |format|
      format.html do
        if params[:with_update_success_message]
          # removes the parameter 'with_update_success_message' with a redirect
          # and returns with a flash success message within the redirect.
          edit_url = edit_project_key_translation_url(@project, @key, @translation)
          redirect_to edit_url, flash: { success: t('controllers.translations.update.success') }
        end
      end
    end
  end

  # Updates a Translation with new translated copy. If the translated copy is
  # blank, the translation will be considered to have been "erased" (marked as
  # untranslated) unless the `blank_string` parameter is set.
  #
  # Routes
  # ------
  #
  # * `PATCH /projects/:project_id/keys/:key_id/translations/:id`
  #
  # Path Parameters
  # ---------------
  #
  # |              |                                    |
  # |:-------------|:-----------------------------------|
  # | `project_id` | The slug of a Project.             |
  # | `key_id`     | The slug of a Key in that project. |
  # | `id`         | The ID of a Translation.           |
  #
  # Body Parameters
  # ---------------
  #
  # |               |                                               |
  # |:--------------|:----------------------------------------------|
  # | `translation` | Parameterized hash of Translation attributes. |
  #
  # Query Parameters
  # ----------------
  #
  # |                |                                              |
  # |:---------------|:---------------------------------------------|
  # | `blank_string` | If true, a blank translated copy is allowed. |

  def update
    # translators cannot modify approved copy
    return head(:forbidden) if @translation.approved? && current_user.role == 'translator'

    mediator = TranslationUpdateMediator.new(@translation, current_user, params)
    mediator.update!

    respond_with(@translation, location: project_key_translation_url(@project, @key, @translation)) do |format|
      format.json do
        if mediator.success?
          render json: decorate([@translation]).first
        else
          render json: mediator.errors, status: :unprocessable_entity
        end
      end
      sha = (params[:commit] == 'Save' ? nil : params[:commit])
      edit_url = (sha.present? ?
        edit_project_key_translation_url(@project, @key, @translation, commit: params[:commit]) :
        edit_project_key_translation_url(@project, @key, @translation)
      )
      format.html do
        if mediator.success?
          redirect_to edit_url, flash: { success: t('controllers.translations.update.success') }
        else
          redirect_to edit_url, flash: { alert: mediator.errors.unshift(t('controllers.translations.update.failure')) }
        end
      end
    end
  end

  # Update a translation's key, hidden_in_search, to exclude the key and corresponding translations
  # in search result.
  #
  # Routes
  # ------
  # * `PATCH /projects/:project_id/keys/:key_id/translations/:translation_id/hide_in_search`
  #
  # Path Parameters
  # ---------------
  #
  # |                  |                                    |
  # |:-----------------|:-----------------------------------|
  # | `project_id`     | The slug of a Project.             |
  # | `key_id`         | The slug of a Key in that project. |
  # | `translation_id` | The ID of a Translation.           |

  def hide_in_search
    if @key.hidden_in_search
      redirect_to edit_project_key_translation_url(@project, @key, @translation), flash: { alert: 'This translation state has been modified, please refresh and try again'}
    else
      change_hidden_in_search_to(true)
      redirect_to edit_project_key_translation_url(@project, @key, @translation), flash: { success: 'This translation is now hidden from search'}
    end
  end

  # Update a translation's key, hidden_in_search, to include the key and corresponding translations
  # in search result.
  #
  # Routes
  # ------
  # * `PATCH /projects/:project_id/keys/:key_id/translations/:translation_id/show_in_search`
  #
  # Path Parameters
  # ---------------
  #
  # |                  |                                    |
  # |:-----------------|:-----------------------------------|
  # | `project_id`     | The slug of a Project.             |
  # | `key_id`         | The slug of a Key in that project. |
  # | `translation_id` | The ID of a Translation.           |

  def show_in_search
    unless @key.hidden_in_search
      redirect_to edit_project_key_translation_url(@project, @key, @translation), flash: { alert: 'This translation state has been modified, please refresh and try again'}
    else
      change_hidden_in_search_to(false)
      redirect_to edit_project_key_translation_url(@project, @key, @translation), flash: { success: 'This translation is now available in search'}
    end
  end

  # Returns the first eligible Translation Unit that meets the following
  # requirements:
  #
  # * in the same locale,
  # * and has the same source copy.
  #
  # If multiple Translation Units match, priority is given to the most recently
  # updated Translation. If no Translation Units match in the same locale,
  # {Locale#fallbacks fallback} locales are tried in order. Under each
  # fallback locale, a Translation Unit is located that shares the same project, same
  # key, and same source copy. If no match is found, that same fallback locale
  # is searched for a Translation Unit with the same source copy, priority given to
  # the most recently modified Translation. If no match is found, the next more
  # general fallback locale is attempted.
  #
  # In all cases, the candidate Translation must be approved to match.
  #
  # Routes
  # ------
  #
  # * `GET /projects/:project_id/keys/:key_id/translations/:id/match`
  #
  # Path Parameters
  # ---------------
  #
  # |              |                                    |
  # |:-------------|:-----------------------------------|
  # | `project_id` | The slug of a Project.             |
  # | `key_id`     | The slug of a Key in that project. |
  # | `id`         | The ID of a Translation.           |
  #
  # Response
  # ========
  #
  # Returns 204 Not Content and an empty body if no match is found.

  def match
    @match = MatchTranslationsFinder.new(@translation).find_first_match_translation
    return head(:no_content) unless @match
    respond_with @match, location: project_key_translation_url(@project, @key, @translation)
  end

  #TODO return all matches, show popup

  # Returns up to 5 best fuzzy matching Translations that meets the following
  # requirements:
  #
  # * in the same locale,
  #
  # If multiple Translations match, priority is given to the most closely
  # matching Translations.
  #
  # Routes
  # ------
  #
  # * `GET /projects/:project_id/keys/:key_id/translations/:id/fuzzy_match`
  #
  # Path Parameters
  # ---------------
  #
  # |              |                                    |
  # |:-------------|:-----------------------------------|
  # | `project_id` | The slug of a Project.             |
  # | `key_id`     | The slug of a Key in that project. |
  # | `id`         | The ID of a Translation.           |
  #

  def fuzzy_match
    query_filter = params[:source_copy] || @translation.source_copy
    finder = FuzzyMatchTranslationsFinder.new(query_filter, @translation)
    respond_to do |format|
      format.json do
        @results = finder.find_fuzzy_match
        render json: decorate_fuzzy_match(@results, query_filter).to_json
      end
    end
  end

  private

  def find_project
    @project = Project.find_from_slug!(params[:project_id])
  end

  def find_key
    @key = @project.keys.find_by_id!(params[:key_id])
  end

  def find_translation
    @translation = @key.translations.where(rfc5646_locale: params[:id]).first!
  end

  def find_issues
    @issues = @translation.issues.includes(:user, comments: :user).references(:comments).order_default_with_comments
    @issue = Issue.new_with_defaults
  end

  def translation_params
    params.require(:translation).permit(:copy, :notes)
  end

  def change_hidden_in_search_to(state)
    @key.update!(hidden_in_search: state)
    @translation.update_elasticsearch_index
  end

  def decorate_fuzzy_match(translations, source_copy)
    translations = translations.map do |translation|
      {
          source_copy: translation.source_copy,
          copy: translation.copy,
          match_percentage: source_copy.similar(translation.source_copy),
          rfc5646_locale: translation.rfc5646_locale,
          project_name: translation.key.project.name.truncate(30)
      }
    end.reject { |t| t[:match_percentage] < FuzzyMatchTranslationsFinder::MINIMUM_FUZZY_MATCH }
    translations.sort! { |a, b| b[:match_percentage] <=> a[:match_percentage] }
  end
end
